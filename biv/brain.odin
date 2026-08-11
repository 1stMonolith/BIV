package biv

import "core:math/rand"
import "base:runtime"
import "core:time"

Lobe_ID :: enum u8 {
    Drive,
    Source,
    Verb,
    Noun,
    Sense,
    Decision,
    Attention,
    Concept,
}

// Drive lobe (16 cells, 13 used in C1)
Drive :: enum u8 {
    Pain              = 0,
    Need_For_Pleasure = 1,
    Hunger            = 2,
    Coldness          = 3,
    Hotness           = 4,
    Tiredness         = 5,
    Sleepiness        = 6,
    Loneliness        = 7,
    Crowdedness       = 8,
    Fear              = 9,
    Boredom           = 10,
    Anger             = 11,
    Sex_Drive         = 12,
    // 13–15 unused
}

// Verb / Decision lobe actions (16 cells)
Verb :: enum u8 {
    Quiescent = 0, // stay / do nothing
    Push      = 1, // activate 1  (eat food, etc.)
    Pull      = 2, // activate 2
    Stop      = 3, // deactivate
    Come      = 4, // approach
    Run       = 5, // retreat
    Get       = 6,
    Drop      = 7,
    Think     = 8, // say need / what
    Sleep     = 9,
    Left      = 10,
    Right     = 11,
    // 12–15 unused
}

// Noun / Source / Attention object classes (40 cells)
Noun :: enum u8 {
    Self        = 0,
    Hand        = 1,
    Call_Button = 2,
    Water       = 3,
    Plant       = 4,
    Egg         = 5,
    Food        = 6,
    Drink       = 7,
    Vendor      = 8,
    Music       = 9,
    Animal      = 10,
    Fire        = 11,
    Shower      = 12,
    Toy         = 13,
    BigToy      = 14,
    Weed        = 15,
    Incubator   = 16,
    // 17–25 unused
    Vehicle     = 26,
    Lift        = 27,
    Computer    = 28,
    Fun         = 29,
    Bang        = 30,
    // 31–35 unused
    Creature1   = 36,
    Creature2   = 37,
    Creature3   = 38,
    Creature4   = 39,
}

// General Sense lobe events / features (32 cells)
Sense :: enum u8 {
    BeenPatted     = 0,
    BeenSlapped    = 1,
    BumpedWall     = 2,
    NearWall       = 3,
    InVehicle      = 4,
    UserSpoken     = 5,
    CreatureSpoken = 6,
    OwnKindSpoken  = 7,
    AudibleEvent   = 8,
    VisibleEvent   = 9,
    ItApproaching  = 10,
    ItRetreating   = 11,
    ItNearMe       = 12,
    ItActive       = 13,
    ItObject       = 14,
    ItCreature     = 15,
    ItSibling      = 16,
    ItParent       = 17,
    ItChild        = 18,
    ItOppositeSex  = 19,
    // 20+ were unused
}

Neuron_Index :: distinct u16

LOBE_SIZES := [Lobe_ID]int{
    .Drive      = 16,
    .Source     = 40,
    .Verb       = 16,
    .Noun       = 40,
    .Sense      = 32,
    .Decision   = 16,
    .Attention  = 40,
    .Concept    = 640,
}

Dendrite :: struct {
    source_lobe : Lobe_ID,
    source_idx  : Neuron_Index,
    stw         : f32, // short-term weight
    ltw         : f32, // long-term weight
    susceptible : f32, // how recently / strongly it fired
    strength    : f32, // overall health of the connection
}

Neuron :: struct {
    state     : f32,
    output    : f32,
    rest      : f32,
    threshold : f32, // Neuron will not fire unless state is greater than this threshold
    leakage   : f32, // Speed at which the state will drop from is current value to its rest state
}

Lobe :: struct {
    id          : Lobe_ID,
    neurons     : []Neuron,
    dendrites_0 : [][]Dendrite, // type 0 – usually excitatory
    dendrites_1 : [][]Dendrite, // type 1 – usually inhibitory
    wta         : bool,
    update      : proc(lobe: ^Lobe, brain: ^Brain),
}

Brain :: struct {
    lobes             : [Lobe_ID]Lobe,
    reward            : f32, // 0..1 (set by biochemistry / external code)
    punish            : f32, // 0..1 (set by biochemistry / external code)
    chemicals         : [4]f32,
    tick              : u64,

    // Learning parameters (tweakable)
    learning_rate        : f32, // how fast STW moves
    ltw_rate             : f32, // how fast LTW tracks STW
    susceptibility_decay : f32,
    migration_threshold  : f32, // below this strength → migrate
}

create :: proc(allocator := context.allocator) -> ^Brain {
    b := new(Brain, allocator)
    rand.reset(u64(time.time_to_unix(time.now())))

    // Default learning hyper-parameters
    b.learning_rate        = 0.12
    b.ltw_rate             = 0.02
    b.susceptibility_decay = 0.85
    b.migration_threshold  = 0.04

    for id in Lobe_ID {
        size := LOBE_SIZES[id]
        lobe := &b.lobes[id]
        lobe.id = id
        lobe.neurons     = make([]Neuron, size, allocator)
        lobe.dendrites_0 = make([][]Dendrite, size, allocator)
        lobe.dendrites_1 = make([][]Dendrite, size, allocator)

        for &n in lobe.neurons {
            n.rest      = 0.00
            n.threshold = 0.10
            n.leakage   = 0.05
        }
        lobe.wta = (id == .Source) | (id == .Verb) | (id == .Noun) | (id == .Decision) | (id == .Attention)
    }

    b.lobes[.Concept].update    = update_concept
    b.lobes[.Decision].update   = update_decision
    b.lobes[.Attention].update  = update_attention

    wire_random_dendrites(b)
    return b
}

destroy :: proc(b: ^Brain) {
    if b == nil do return
    for &lobe in b.lobes {
        for list in lobe.dendrites_0 do delete(list)
        for list in lobe.dendrites_1 do delete(list)
        delete(lobe.dendrites_0)
        delete(lobe.dendrites_1)
        delete(lobe.neurons)
    }
    free(b)
}

clear_dendrites :: proc(lobe: ^Lobe) {
    for i in 0..<len(lobe.dendrites_0) {
        delete(lobe.dendrites_0[i])
        lobe.dendrites_0[i] = nil
    }
    for i in 0..<len(lobe.dendrites_1) {
        delete(lobe.dendrites_1[i])
        lobe.dendrites_1[i] = nil
    }
}

make_dendrite :: proc(source_lobe: Lobe_ID, source_idx: int) -> Dendrite {
    strength := 0.18 + rand.float32_range(0.0, 0.30)
    return Dendrite{
        source_lobe = source_lobe,
        source_idx  = Neuron_Index(source_idx),
        stw         = strength,
        ltw         = strength,
        susceptible = 0.0,
        strength    = strength,
    }
}

wire_random_dendrites :: proc(b: ^Brain) {
    // Concept
    concept := &b.lobes[.Concept]
    clear_dendrites(concept)

    drive_size     := LOBE_SIZES[.Drive]
    verb_size      := LOBE_SIZES[.Verb]
    sense_size     := LOBE_SIZES[.Sense]
    attention_size := LOBE_SIZES[.Attention]

    for i in 0..<len(concept.neurons) {
        concept.dendrites_0[i] = make([]Dendrite, 4)
        concept.dendrites_0[i][0] = make_dendrite(.Drive,     rand.int_max(drive_size))
        concept.dendrites_0[i][1] = make_dendrite(.Verb,      rand.int_max(verb_size))
        concept.dendrites_0[i][2] = make_dendrite(.Sense,     rand.int_max(sense_size))
        concept.dendrites_0[i][3] = make_dendrite(.Attention, rand.int_max(attention_size))
    }

    // Decision
    decision := &b.lobes[.Decision]
    clear_dendrites(decision)
    concept_size := LOBE_SIZES[.Concept]
    DENDRITES_PER :: 128

    for i in 0..<len(decision.neurons) {
        decision.dendrites_0[i] = make([]Dendrite, DENDRITES_PER)
        decision.dendrites_1[i] = make([]Dendrite, DENDRITES_PER)
        for j in 0..<DENDRITES_PER {
            decision.dendrites_0[i][j] = make_dendrite(.Concept, rand.int_max(concept_size))
            decision.dendrites_1[i][j] = make_dendrite(.Concept, rand.int_max(concept_size))
        }
    }

    // Attention ← Source + Noun
    attention := &b.lobes[.Attention]
    clear_dendrites(attention)
    for i in 0..<len(attention.neurons) {
        attention.dendrites_0[i] = make([]Dendrite, 1)
        attention.dendrites_0[i][0] = make_dendrite(.Source, i % LOBE_SIZES[.Source])
        attention.dendrites_1[i] = make([]Dendrite, 1)
        attention.dendrites_1[i][0] = make_dendrite(.Noun, i % LOBE_SIZES[.Noun])
    }
}

neuron_output :: proc(n: Neuron) -> f32 {
    return max(0.0, n.state - n.threshold)
}

apply_leakage :: proc(n: ^Neuron) {
    n.state += (n.rest - n.state) * n.leakage
    n.output = neuron_output(n^)
}

// Sum and also mark contributing dendrites as susceptible
sum_dendrites_and_mark :: proc(dendrites: []Dendrite, brain: ^Brain) -> f32 {
    total: f32 = 0
    for &d in dendrites {
        src_lobe := &brain.lobes[d.source_lobe]
        if int(d.source_idx) >= len(src_lobe.neurons) do continue

        src_out := src_lobe.neurons[d.source_idx].output
        contribution := src_out * d.stw
        total += contribution

        // Mark susceptibility proportional to how much this dendrite contributed
        if src_out > 0.02 {
            d.susceptible = min(1.0, d.susceptible + src_out * 0.6)
        }
    }
    return total
}

apply_wta :: proc(lobe: ^Lobe) {
    if !lobe.wta || len(lobe.neurons) == 0 do return
    best_idx := 0
    best_val := lobe.neurons[0].state
    for i in 1..<len(lobe.neurons) {
        if lobe.neurons[i].state > best_val {
            best_val = lobe.neurons[i].state
            best_idx = i
        }
    }
    for i in 0..<len(lobe.neurons) {
        lobe.neurons[i].output = (i == best_idx) ? neuron_output(lobe.neurons[i]) : 0
    }
}

update_concept :: proc(lobe: ^Lobe, brain: ^Brain) {
    for i in 0..<len(lobe.neurons) {
        n := &lobe.neurons[i]
        d0 := lobe.dendrites_0[i]

        if len(d0) == 0 {
            n.state = 0
            apply_leakage(n)
            continue
        }

        all_active := true
        min_val: f32 = 1.0
        for &d in d0 {
            src_out := brain.lobes[d.source_lobe].neurons[d.source_idx].output
            if src_out <= 0.01 {
                all_active = false
                break
            }
            min_val = min(min_val, src_out * d.stw)
            d.susceptible = min(1.0, d.susceptible + src_out * 0.5)
        }
        n.state = all_active ? min_val : 0.0
        apply_leakage(n)
    }
}

update_decision :: proc(lobe: ^Lobe, brain: ^Brain) {
    for i in 0..<len(lobe.neurons) {
        n := &lobe.neurons[i]
        excitatory := sum_dendrites_and_mark(lobe.dendrites_0[i], brain)
        inhibitory := sum_dendrites_and_mark(lobe.dendrites_1[i], brain)
        n.state = n.state + excitatory - inhibitory
        apply_leakage(n)
    }
    apply_wta(lobe)
}

update_attention :: proc(lobe: ^Lobe, brain: ^Brain) {
    for i in 0..<len(lobe.neurons) {
        n := &lobe.neurons[i]
        a := sum_dendrites_and_mark(lobe.dendrites_0[i], brain)
        b := sum_dendrites_and_mark(lobe.dendrites_1[i], brain)
        n.state = n.state + a + b
        apply_leakage(n)
    }
    apply_wta(lobe)
}

learn_dendrite :: proc(d: ^Dendrite, reward, punish: f32, is_excitatory: bool, b: ^Brain) {
    // only recently active dendrites learn
    if d.susceptible < 0.01 do return

    // Direction of change
    delta: f32
    if is_excitatory {
        delta = (reward - punish) * d.susceptible
    } else {
        delta = (punish - reward) * d.susceptible   // inhibitory: opposite polarity
    }

    // Update short-term weight
    d.stw = clamp(d.stw + delta * b.learning_rate, 0.0, 1.0)

    // Slow tracking into long-term weight
    d.ltw = d.ltw + (d.stw - d.ltw) * b.ltw_rate

    // Strength is influenced by both
    d.strength = 0.6*d.ltw + 0.4*d.stw

    // Decay susceptibility
    d.susceptible *= b.susceptibility_decay
}

migrate_dendrite :: proc(d: ^Dendrite, b: ^Brain) {
    size := LOBE_SIZES[d.source_lobe]
    d.source_idx  = Neuron_Index(rand.int_max(size))
    d.stw         = 0.15 + rand.float32_range(0.0, 0.2)
    d.ltw         = d.stw
    d.strength    = d.stw
    d.susceptible = 0.0
}

// Apply learning to a whole lobe
learn_lobe :: proc(lobe: ^Lobe, b: ^Brain, type0_is_excitatory: bool) {
    for i in 0..<len(lobe.neurons) {
        // Type 0
        for &d in lobe.dendrites_0[i] {
            learn_dendrite(&d, b.reward, b.punish, type0_is_excitatory, b)
            if d.strength < b.migration_threshold {
                migrate_dendrite(&d, b)
            }
        }
        // Type 1
        for &d in lobe.dendrites_1[i] {
            learn_dendrite(&d, b.reward, b.punish, !type0_is_excitatory, b)
            if d.strength < b.migration_threshold {
                migrate_dendrite(&d, b)
            }
        }
    }
}

learn :: proc(b: ^Brain) {
    // Concept learns from Perception (all type-0, treated as excitatory)
    learn_lobe(&b.lobes[.Concept], b, true)

    // Decision learns from Concept
    // type-0 = excitatory, type-1 = inhibitory
    learn_lobe(&b.lobes[.Decision], b, true)

    // Optional: also allow Attention to learn a little
    // learn_lobe(&b.lobes[.Attention], b, true)

    // Decay global signals so they don’t stay high forever
    b.reward *= 0.92
    b.punish *= 0.92
}

tick :: proc(b: ^Brain) {
    b.tick += 1

    for id in Lobe_ID {
        if id == .Concept || id == .Decision || id == .Attention do continue
        lobe := &b.lobes[id]
        if lobe.update == nil {
            for &n in lobe.neurons do apply_leakage(&n)
            if lobe.wta do apply_wta(lobe)
        }
    }

    if b.lobes[.Concept].update    != nil do b.lobes[.Concept].update(&b.lobes[.Concept], b)
    if b.lobes[.Decision].update   != nil do b.lobes[.Decision].update(&b.lobes[.Decision], b)
    if b.lobes[.Attention].update  != nil do b.lobes[.Attention].update(&b.lobes[.Attention], b)
}

tick_and_learn :: proc(b: ^Brain) {
    tick(b)
    learn(b)
}

set_reward :: proc(b: ^Brain, value: f32) {
    b.reward = clamp(value, 0, 1)
}

set_punish :: proc(b: ^Brain, value: f32) {
    b.punish = clamp(value, 0, 1)
}

set_drive :: proc(b: ^Brain, drive: Drive, value: f32) {
    idx := int(drive)
    if idx < 0 || idx >= LOBE_SIZES[.Drive] do return
    n := &b.lobes[.Drive].neurons[drive]
    n.state = clamp(value, 0, 1)
    n.output = neuron_output(n^)
}

speak_verb :: proc(b: ^Brain, verb: Verb, strength: f32 = 1.0) {
    idx := int(verb)
    if idx < 0 || idx >= LOBE_SIZES[.Verb] do return
    n := &b.lobes[.Verb].neurons[verb]
    n.state = strength
    n.output = neuron_output(n^)
}

speak_noun :: proc(b: ^Brain, noun: Noun, strength: f32 = 1.0) {
    idx := int(noun)
    if idx < 0 || idx >= LOBE_SIZES[.Noun] do return
    n := &b.lobes[.Noun].neurons[noun]
    n.state = strength
    n.output = neuron_output(n^)
}

set_sense :: proc(b: ^Brain, sense: Sense, value: f32) {
    idx := int(sense)
    if idx < 0 || idx >= LOBE_SIZES[.Sense] do return
    n := &b.lobes[.Sense].neurons[sense]
    n.state = clamp(value, 0, 1)
    n.output = neuron_output(n^)
}

set_source :: proc(b: ^Brain, object: Noun, value: f32) {
    idx := int(object)
    if idx < 0 || idx >= LOBE_SIZES[.Source] do return
    n := &b.lobes[.Source].neurons[idx]
    n.state = clamp(value, 0, 1)
    n.output = neuron_output(n^)
}

get_decision :: proc(b: ^Brain) -> Verb {
    return Verb(get_decision_index(b))   // rename the old int version
}

get_decision_index :: proc(b: ^Brain) -> int {
    lobe := &b.lobes[.Decision]
    best, best_val := 0, lobe.neurons[0].output
    for i in 1..<len(lobe.neurons) {
        if lobe.neurons[i].output > best_val {
            best_val = lobe.neurons[i].output
            best = i
        }
    }
    return best
}

get_attention :: proc(b: ^Brain) -> Noun {
    return Noun(get_attention_index(b))
}

get_attention_index :: proc(b: ^Brain) -> int {
    lobe := &b.lobes[.Attention]
    best, best_val := 0, lobe.neurons[0].output
    for i in 1..<len(lobe.neurons) {
        if lobe.neurons[i].output > best_val {
            best_val = lobe.neurons[i].output
            best = i
        }
    }
    return best
}
