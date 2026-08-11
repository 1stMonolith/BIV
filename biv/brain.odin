package biv

import "core:math/rand"
import "base:runtime"
import "core:time"

Lobe_ID :: enum u8 {
    Perception,
    Drive,
    Source,
    Verb,
    Noun,
    General_Sense,
    Decision,
    Attention,
    Concept,
}

Neuron_Index :: distinct u16

LOBE_SIZES := [Lobe_ID]int{
    .Perception    = 112,
    .Drive         = 16,
    .Source        = 40,
    .Verb          = 16,
    .Noun          = 40,
    .General_Sense = 32,
    .Decision      = 16,
    .Attention     = 40,
    .Concept       = 640,
}

PERCEPTION_LAYOUT :: struct {
    drive_start         : int,
    drive_count         : int,
    verb_start          : int,
    verb_count          : int,
    general_sense_start : int,
    general_sense_count : int,
    attention_start     : int,
    attention_count     : int,
}

DEFAULT_PERCEPTION_LAYOUT := PERCEPTION_LAYOUT{
    drive_start         = 0,
    drive_count         = 16,
    verb_start          = 16,
    verb_count          = 16,
    general_sense_start = 32,
    general_sense_count = 32,
    attention_start     = 64,
    attention_count     = 40,
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
    state, output, rest, threshold, leakage : f32,
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
    perception_layout : PERCEPTION_LAYOUT,
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
    
    b.perception_layout = DEFAULT_PERCEPTION_LAYOUT

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

    b.lobes[.Perception].update = update_perception
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
    // Concept ← Perception (1–3 inputs)
    concept := &b.lobes[.Concept]
    clear_dendrites(concept)
    perc_size := LOBE_SIZES[.Perception]

    for i in 0..<len(concept.neurons) {
        n_inputs := 1 + rand.int_max(3)
        concept.dendrites_0[i] = make([]Dendrite, n_inputs)
        used := make([]bool, perc_size, context.temp_allocator)

        for j in 0..<n_inputs {
            src: int
            for {
                src = rand.int_max(perc_size)
                if !used[src] { used[src] = true; break }
            }
            concept.dendrites_0[i][j] = make_dendrite(.Perception, src)
        }
    }

    // Decision ← Concept
    decision := &b.lobes[.Decision]
    clear_dendrites(decision)
    concept_size := LOBE_SIZES[.Concept]
    DENDRITES_PER :: 40

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

update_perception :: proc(lobe: ^Lobe, brain: ^Brain) {
    layout := brain.perception_layout
    perc := lobe.neurons
    for &n in perc { n.state = 0; n.output = 0 }

    copy_slice :: proc(dst: []Neuron, src: []Neuron, start, count: int) {
        for i in 0..<count {
            if i < len(src) && start+i < len(dst) {
                dst[start+i].state  = src[i].output
                dst[start+i].output = src[i].output
            }
        }
    }

    copy_slice(perc, brain.lobes[.Drive].neurons,         layout.drive_start,         layout.drive_count)
    copy_slice(perc, brain.lobes[.Verb].neurons,          layout.verb_start,          layout.verb_count)
    copy_slice(perc, brain.lobes[.General_Sense].neurons, layout.general_sense_start, layout.general_sense_count)
    copy_slice(perc, brain.lobes[.Attention].neurons,     layout.attention_start,     layout.attention_count)
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
            // mark susceptibility
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

migrate_dendrite :: proc(d: ^Dendrite, allowed_lobe: Lobe_ID, b: ^Brain) {
    size := LOBE_SIZES[allowed_lobe]
    new_idx := rand.int_max(size)
    d.source_lobe = allowed_lobe
    d.source_idx  = Neuron_Index(new_idx)
    // Reset to a modest new strength so it can be tested again
    d.stw = 0.15 + rand.float32_range(0.0, 0.2)
    d.ltw = d.stw
    d.strength = d.stw
    d.susceptible = 0.0
}

// Apply learning to a whole lobe
learn_lobe :: proc(lobe: ^Lobe, b: ^Brain, type0_is_excitatory: bool) {
    for i in 0..<len(lobe.neurons) {
        // Type 0
        for &d in lobe.dendrites_0[i] {
            learn_dendrite(&d, b.reward, b.punish, type0_is_excitatory, b)
            if d.strength < b.migration_threshold {
                // Concept dendrites migrate within Perception
                // Decision dendrites migrate within Concept
                target := (lobe.id == .Concept) ? Lobe_ID.Perception : Lobe_ID.Concept
                migrate_dendrite(&d, target, b)
            }
        }
        // Type 1
        for &d in lobe.dendrites_1[i] {
            learn_dendrite(&d, b.reward, b.punish, !type0_is_excitatory, b)
            if d.strength < b.migration_threshold {
                target := (lobe.id == .Concept) ? Lobe_ID.Perception : Lobe_ID.Concept
                migrate_dendrite(&d, target, b)
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

    if b.lobes[.Perception].update != nil do b.lobes[.Perception].update(&b.lobes[.Perception], b)
    if b.lobes[.Concept].update    != nil do b.lobes[.Concept].update(&b.lobes[.Concept], b)
    if b.lobes[.Decision].update   != nil do b.lobes[.Decision].update(&b.lobes[.Decision], b)
    if b.lobes[.Attention].update  != nil do b.lobes[.Attention].update(&b.lobes[.Attention], b)

    for id in Lobe_ID {
        lobe := &b.lobes[id]
        if lobe.update == nil {
            for &n in lobe.neurons do apply_leakage(&n)
            if lobe.wta do apply_wta(lobe)
        }
    }
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

set_drive :: proc(b: ^Brain, drive: int, value: f32) {
    if drive < 0 || drive >= LOBE_SIZES[.Drive] do return
    n := &b.lobes[.Drive].neurons[drive]
    n.state = clamp(value, 0, 1)
    n.output = neuron_output(n^)
}

speak_verb :: proc(b: ^Brain, verb: int, strength: f32 = 1.0) {
    if verb < 0 || verb >= LOBE_SIZES[.Verb] do return
    n := &b.lobes[.Verb].neurons[verb]
    n.state = strength
    n.output = neuron_output(n^)
}

speak_noun :: proc(b: ^Brain, noun: int, strength: f32 = 1.0) {
    if noun < 0 || noun >= LOBE_SIZES[.Noun] do return
    n := &b.lobes[.Noun].neurons[noun]
    n.state = strength
    n.output = neuron_output(n^)
}

set_general_sense :: proc(b: ^Brain, sense: int, value: f32) {
    if sense < 0 || sense >= LOBE_SIZES[.General_Sense] do return
    n := &b.lobes[.General_Sense].neurons[sense]
    n.state = clamp(value, 0, 1)
    n.output = neuron_output(n^)
}

set_source :: proc(b: ^Brain, object_class: int, value: f32) {
    if object_class < 0 || object_class >= LOBE_SIZES[.Source] do return
    n := &b.lobes[.Source].neurons[object_class]
    n.state = clamp(value, 0, 1)
    n.output = neuron_output(n^)
}

get_decision :: proc(b: ^Brain) -> int {
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

get_attention :: proc(b: ^Brain) -> int {
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
