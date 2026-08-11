package biv

import rl "vendor:raylib"
import "core:fmt"
import "core:strings"

CELL_SIZE :: 14  // pixels per neuron
GRID_PAD  :: 40  // margin around the whole brain
UI_WIDTH  :: 320 // right-side control panel

brain_pixel_width  :: 64 * CELL_SIZE
brain_pixel_height :: 48 * CELL_SIZE

Lobe_Rect :: struct {
    id     : Lobe_ID,
    name   : string,
    // position in the *logical* 64×48 grid
    gx, gy : int,
    gw, gh : int, // width/height in cells
    // computed screen rect
    screen : rl.Rectangle,
}

// Simplified dendrite reference for the list
Dendrite_Ref :: struct {
    src_lobe, dst_lobe : Lobe_ID,
    src_idx,  dst_idx  : Neuron_Index,
    stw                : f32,
    is_excitatory      : bool,
    label              : string,
}

UI_State :: struct {
// Sensory selectors
    drive_index   : i32,
    source_index  : i32,
    sense_index   : i32,
    verb_index    : i32,
    noun_index    : i32,

    drive_value   : f32,
    source_value  : f32,
    sense_value   : f32,

    // Dendrite list
    dendrites           : [dynamic]Dendrite_Ref,
    dendrite_labels     : [dynamic]cstring, // for GuiListView
    dendrite_scroll     : i32,
    dendrite_active     : i32,              // -1 = none selected
    show_all_dendrites  : bool,

    // Temporary cstring buffers for the fixed lists
    drive_labels  : [dynamic]cstring,
    source_labels : [dynamic]cstring,
    sense_labels  : [dynamic]cstring,
    verb_labels   : [dynamic]cstring,
    noun_labels   : [dynamic]cstring,
}

LOBE_LAYOUT := [Lobe_ID]Lobe_Rect{
    .Perception    = {id = .Perception,    name = "Perception",    gx =  4, gy = 13, gw =  7, gh = 16},
    .Drive         = {id = .Drive,         name = "Drive",         gx = 34, gy = 30, gw =  8, gh =  2},
    .Source        = {id = .Source,        name = "Source",        gx = 15, gy = 24, gw =  8, gh =  5},
    .Verb          = {id = .Verb,          name = "Verb",          gx = 37, gy = 24, gw =  8, gh =  2},
    .Noun          = {id = .Noun,          name = "Noun",          gx = 21, gy =  3, gw = 20, gh =  2},
    .General_Sense = {id = .General_Sense, name = "General Sense", gx = 32, gy = 34, gw =  8, gh =  4},
    .Decision      = {id = .Decision,      name = "Decision",      gx = 53, gy = 15, gw =  1, gh = 16},
    .Attention     = {id = .Attention,     name = "Attention",     gx = 44, gy = 30, gw =  5, gh =  8},
    .Concept       = {id = .Concept,       name = "Concept",       gx = 12, gy =  6, gw = 40, gh = 16},
}

visualizer_init :: proc(ui: ^UI_State) {
    ui.drive_index  = 2          // Hunger by default
    ui.source_index = 6          // Food
    ui.sense_index  = 12         // It_Near_Me
    ui.dendrite_active = -1
    ui.drive_value  = 0.8
    ui.source_value = 0.7
    ui.sense_value  = 0.6

    build_enum_labels(ui)
}

build_enum_labels :: proc(ui: ^UI_State) {
    // Drive
    clear(&ui.drive_labels)
    for d in Drive {
        append(&ui.drive_labels, strings.clone_to_cstring(fmt.tprintf("%v", d), context.allocator))
    }

    // Source / Noun (same indices)
    clear(&ui.source_labels)
    clear(&ui.noun_labels)
    for n in Noun {
        name := fmt.tprintf("%v", n)
        append(&ui.source_labels, strings.clone_to_cstring(name, context.allocator))
        append(&ui.noun_labels,   strings.clone_to_cstring(name, context.allocator))
    }

    // General Sense
    clear(&ui.sense_labels)
    for s in GeneralSense {
        append(&ui.sense_labels, strings.clone_to_cstring(fmt.tprintf("%v", s), context.allocator))
    }

    // Verb
    clear(&ui.verb_labels)
    for v in Verb {
        append(&ui.verb_labels, strings.clone_to_cstring(fmt.tprintf("%v", v), context.allocator))
    }
}

visualizer_destroy :: proc(ui: ^UI_State) {
    for l in ui.drive_labels    do delete(l)
    for l in ui.source_labels   do delete(l)
    for l in ui.sense_labels    do delete(l)
    for l in ui.verb_labels     do delete(l)
    for l in ui.noun_labels     do delete(l)
    for l in ui.dendrite_labels do delete(l)
    for d in ui.dendrites       do delete(d.label)

    delete(ui.drive_labels)
    delete(ui.source_labels)
    delete(ui.sense_labels)
    delete(ui.verb_labels)
    delete(ui.noun_labels)
    delete(ui.dendrite_labels)
    delete(ui.dendrites)
}

// Call once after window is created / on resize
visualizer_update_layout :: proc(view_x, view_y: f32) {
    for id in Lobe_ID {
        l := &LOBE_LAYOUT[id]
        l.screen = {
            x = view_x + f32(l.gx) * CELL_SIZE,
            y = view_y + f32(l.gy) * CELL_SIZE,
            width  = f32(l.gw) * CELL_SIZE,
            height = f32(l.gh) * CELL_SIZE,
        }
    }
}

// Returns the screen rectangle of a specific neuron
neuron_rect :: proc(id: Lobe_ID, idx: int) -> rl.Rectangle {
    l := LOBE_LAYOUT[id]
    local_x := idx % l.gw
    local_y := idx / l.gw
    return {
        x = l.screen.x + f32(local_x) * CELL_SIZE,
        y = l.screen.y + f32(local_y) * CELL_SIZE,
        width  = CELL_SIZE - 1,
        height = CELL_SIZE - 1,
    }
}

// Map neuron output (0..1) → colour
neuron_color :: proc(value: f32) -> rl.Color {
    // dark blue → cyan → yellow → red
    t := clamp(value, 0, 1)
    if t < 0.33 {
        return rl.Color{
            u8(t * 3 * 40),
            u8(t * 3 * 80),
            u8(80 + t * 3 * 175),
            255,
        }
    } else if t < 0.66 {
        u := (t - 0.33) * 3
        return rl.Color{u8(u * 255), u8(180 + u * 75), u8(255 - u * 200), 255}
    } else {
        u := (t - 0.66) * 3
        return rl.Color{255, u8(255 - u * 200), 0, 255}
    }
}

visualizer_draw_brain :: proc(brain: ^Brain, selected_dendrites: []Dendrite_Ref) {
    // Background grid (subtle)
    for y in 0..<48 {
        for x in 0..<64 {
            rl.DrawRectangleLines(
                i32(GRID_PAD + x * CELL_SIZE),
                i32(GRID_PAD + y * CELL_SIZE),
                CELL_SIZE, CELL_SIZE,
                {30, 30, 40, 255},
            )
        }
    }

    // Lobes + neurons
    for id in Lobe_ID {
        lobe   := &brain.lobes[id]
        layout := LOBE_LAYOUT[id]

        // Lobe label
        rl.DrawText(
            strings.clone_to_cstring(layout.name, context.temp_allocator),
            i32(layout.screen.x),
            i32(layout.screen.y) - 16,
            14,
            rl.LIGHTGRAY,
        )

        // Individual neurons
        for i in 0..<len(lobe.neurons) {
            r := neuron_rect(id, i)
            c := neuron_color(lobe.neurons[i].output)
            rl.DrawRectangleRec(r, c)
            rl.DrawRectangleLinesEx(r, 1, {20, 20, 30, 180})
        }

        // Lobe border
        rl.DrawRectangleLinesEx(layout.screen, 1, rl.LIGHTGRAY)
    }

    // Selected dendrites as lines
    for ref in selected_dendrites {
        src_r := neuron_rect(ref.src_lobe, int(ref.src_idx))
        dst_r := neuron_rect(ref.dst_lobe, int(ref.dst_idx))

        sx := src_r.x + src_r.width  * 0.5
        sy := src_r.y + src_r.height * 0.5
        
        dx := dst_r.x + dst_r.width  * 0.5
        dy := dst_r.y + dst_r.height * 0.5

        // Colour by weight / type
        col := ref.is_excitatory ? rl.Color{80, 220, 120, 200} : rl.Color{220, 80, 80, 200}

        thickness := 1.0 + ref.stw * 3.0
        rl.DrawLineEx({sx, sy}, {dx, dy}, thickness, col)
    }
}

build_dendrite_list :: proc(brain: ^Brain, ui: ^UI_State) {
    // Free old labels
    for label in ui.dendrite_labels do delete(label)
    clear(&ui.dendrite_labels)
    clear(&ui.dendrites)

    decision := &brain.lobes[.Decision]

    for n in 0..<len(decision.neurons) {
        // Type-0 (excitatory)
        for d in decision.dendrites_0[n] {
            label := fmt.tprintf("C%-3d → Decn%-2d  exc  stw=%.2f", int(d.source_idx), n, d.stw)
            append(&ui.dendrites, Dendrite_Ref{
                src_lobe      = d.source_lobe,
                src_idx       = d.source_idx,
                dst_lobe      = .Decision,
                dst_idx       = Neuron_Index(n),
                stw           = d.stw,
                is_excitatory = true,
                label         = strings.clone(label),
            })
            append(&ui.dendrite_labels, strings.clone_to_cstring(label, context.allocator))
        }
        // Type-1 (inhibitory)
        for d in decision.dendrites_1[n] {
            label := fmt.tprintf("C%-3d → Decn%-2d  inh  stw=%.2f", int(d.source_idx), n, d.stw)
            append(&ui.dendrites, Dendrite_Ref{
                src_lobe      = d.source_lobe,
                src_idx       = d.source_idx,
                dst_lobe      = .Decision,
                dst_idx       = Neuron_Index(n),
                stw           = d.stw,
                is_excitatory = false,
                label         = strings.clone(label),
            })
            append(&ui.dendrite_labels, strings.clone_to_cstring(label, context.allocator))
        }
    }

    ui.dendrite_active = -1
    ui.dendrite_scroll = 0
}

visualizer_draw_ui :: proc(brain: ^Brain, ui: ^UI_State) {
    panel_x := f32(rl.GetScreenWidth()) - UI_WIDTH
    panel_h := f32(rl.GetScreenHeight())

    rl.GuiPanel({panel_x, 0, UI_WIDTH, panel_h}, "BIV Controls")

    y: f32 = 36
    pad: f32 = 10
    width := UI_WIDTH - 2*pad

    // Drive
    rl.GuiGroupBox({panel_x + pad, y, width, 110}, "Drive")
    {
        inner_y := y + 24
        rl.GuiLabel({panel_x + pad + 6, inner_y, 80, 20}, "Select:")
        // ListView for drives (small height)
        drive_text := join_labels(ui.drive_labels[:])
        rl.GuiListView(
            {panel_x + pad + 6, inner_y + 22, width - 12, 50},
            drive_text,
            &ui.drive_index,          // active / selected
            &ui.drive_index,          // scroll index (re-used for simplicity)
        )
        // value slider
        rl.GuiSliderBar(
            {panel_x + pad + 6, inner_y + 78, width - 12, 18},
            "0", "1", &ui.drive_value, 0.0, 1.0,
        )
        if rl.GuiButton({panel_x + pad + 6, inner_y + 100, 100, 22}, "Apply Drive") {
            if ui.drive_index >= 0 && int(ui.drive_index) < len(ui.drive_labels) {
                set_drive(brain, Drive(ui.drive_index), ui.drive_value)
            }
        }
    }
    y += 120

    // Source
    rl.GuiGroupBox({panel_x + pad, y, width, 110}, "Source (object class)")
    {
        inner_y := y + 24
        source_text := join_labels(ui.source_labels[:])
        rl.GuiListView(
            {panel_x + pad + 6, inner_y, width - 12, 50},
            source_text,
            &ui.source_index,
            &ui.source_index,
        )
        rl.GuiSliderBar(
            {panel_x + pad + 6, inner_y + 56, width - 12, 18},
            "0", "1", &ui.source_value, 0.0, 1.0,
        )
        if rl.GuiButton({panel_x + pad + 6, inner_y + 78, 100, 22}, "Apply Source") {
            if ui.source_index >= 0 && int(ui.source_index) < len(ui.source_labels) {
                set_source(brain, Noun(ui.source_index), ui.source_value)
            }
        }
    }
    y += 120

    // General Sense
    rl.GuiGroupBox({panel_x + pad, y, width, 110}, "General Sense")
    {
        inner_y := y + 24
        sense_text := join_labels(ui.sense_labels[:])
        rl.GuiListView(
            {panel_x + pad + 6, inner_y, width - 12, 50},
            sense_text,
            &ui.sense_index,
            &ui.sense_index,
        )
        rl.GuiSliderBar(
            {panel_x + pad + 6, inner_y + 56, width - 12, 18},
            "0", "1", &ui.sense_value, 0.0, 1.0,
        )
        if rl.GuiButton({panel_x + pad + 6, inner_y + 78, 100, 22}, "Apply Sense") {
            if ui.sense_index >= 0 && int(ui.sense_index) < len(ui.sense_labels) {
                set_general_sense(brain, GeneralSense(ui.sense_index), ui.sense_value)
            }
        }
    }
    y += 120

    // Tick button
    if rl.GuiButton({panel_x + pad, y, width/2 - 4, 28}, "Tick") {
        tick(brain)
    }

    // Learn button
    if rl.GuiButton({panel_x + pad + width/2 + 4, y, width/2 - 4, 28}, "Learn") {
        learn(brain)
    }
    y += 40

    // Dendrite list
    remaining := panel_h - y - 20
    rl.GuiGroupBox({panel_x + pad, y, width, remaining}, "Dendrites (Concept → Decision)")

    // “Show all” checkbox
    rl.GuiCheckBox(
        {panel_x + pad + 8, y + 24, 20, 20},
        "Show all dendrites",
        &ui.show_all_dendrites,
    )

    list_y := y + 52
    list_h := remaining - 60

    dendrite_text := join_labels(ui.dendrite_labels[:])
    rl.GuiListView(
        {panel_x + pad + 6, list_y, width - 12, list_h},
        dendrite_text,
        &ui.dendrite_scroll, // scroll offset
        &ui.dendrite_active, // currently selected item
    )
}

// Join a slice of cstrings into the “item1;item2;item3” format raygui expects
join_labels :: proc(labels: []cstring, allocator := context.temp_allocator) -> cstring {
    if len(labels) == 0 do return ""
    b := strings.builder_make(allocator)
    for label, i in labels {
        if i > 0 do strings.write_string(&b, ";")
        strings.write_string(&b, string(label))
    }
    return strings.to_cstring(&b)
}
