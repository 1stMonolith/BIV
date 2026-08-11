package biv

import rl "vendor:raylib"
import "core:fmt"
import "core:strings"

Lobe_Rect :: struct {
    id     : Lobe_ID,
    name   : string,
    // position in the *logical* 64×48 grid
    gx, gy : int,
    gw, gh : int,          // width/height in cells
    // computed screen rect
    screen : rl.Rectangle,
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

CELL_SIZE :: 14  // pixels per neuron
GRID_PAD  :: 40  // margin around the whole brain
UI_WIDTH  :: 320 // right-side control panel

brain_pixel_width  :: 64 * CELL_SIZE
brain_pixel_height :: 48 * CELL_SIZE

// Call once after window is created / on resize
update_layout :: proc(view_x, view_y: f32) {
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

draw_brain :: proc(brain: ^Brain, selected_dendrites: []Dendrite_Ref) {
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
        lobe := &brain.lobes[id]
        layout := LOBE_LAYOUT[id]

        // Lobe border + label
        rl.DrawRectangleLinesEx(layout.screen, 2, rl.LIGHTGRAY)
        rl.DrawText(
            strings.clone_to_cstring(layout.name, context.temp_allocator),
            i32(layout.screen.x),
            i32(layout.screen.y) - 16,
            12,
            rl.RAYWHITE,
        )

        // Individual neurons
        for i in 0..<len(lobe.neurons) {
            r := neuron_rect(id, i)
            col := neuron_color(lobe.neurons[i].output)
            rl.DrawRectangleRec(r, col)
            rl.DrawRectangleLinesEx(r, 1, {20, 20, 30, 180})
        }
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

// Simplified dendrite reference for the list
Dendrite_Ref :: struct {
    src_lobe, dst_lobe : Lobe_ID,
    src_idx,  dst_idx  : Neuron_Index,
    stw                : f32,
    is_excitatory      : bool,
    label              : string,
}

UI_State :: struct {
    // right-panel scroll / selection
    selected_drive   : int,
    selected_source  : int,
    selected_sense   : int,
    selected_verb    : int,
    selected_noun    : int,

    drive_value      : f32,
    source_value     : f32,
    sense_value      : f32,

    // dendrite list
    dendrite_list    : [dynamic]Dendrite_Ref,
    selected_dendrite: int,          // -1 = none
    show_all_dendrites: bool,
}

build_dendrite_list :: proc(brain: ^Brain, ui: ^UI_State) {
    clear(&ui.dendrite_list)

    // show Concept → Decision dendrites
    decision := &brain.lobes[.Decision]
    for ni in 0..<len(decision.neurons) {
        for d in decision.dendrites_0[ni] {
            append(&ui.dendrite_list, Dendrite_Ref{
                src_lobe = d.source_lobe,
                src_idx  = d.source_idx,
                dst_lobe = .Decision,
                dst_idx  = Neuron_Index(ni),
                stw      = d.stw,
                is_excitatory = true,
                label    = fmt.tprintf("C%d → Decn%d (exc %.2f)", d.source_idx, ni, d.stw),
            })
        }
        for d in decision.dendrites_1[ni] {
            append(&ui.dendrite_list, Dendrite_Ref{
                src_lobe = d.source_lobe,
                src_idx  = d.source_idx,
                dst_lobe = .Decision,
                dst_idx  = Neuron_Index(ni),
                stw      = d.stw,
                is_excitatory = false,
                label    = fmt.tprintf("C%d → Decn%d (inh %.2f)", d.source_idx, ni, d.stw),
            })
        }
    }
    // TODO: add Concept←Perception, Attention←Source/Noun, etc.
}

draw_ui :: proc(brain: ^Brain, ui: ^UI_State) {
    panel_x := f32(rl.GetScreenWidth() - UI_WIDTH)
    rl.GuiPanel({panel_x, 0, UI_WIDTH, f32(rl.GetScreenHeight())}, "Controls")

    y: f32 = 40
    line :: 28

    // Drive
    rl.GuiLabel({panel_x + 10, y, 200, 20}, "Drive")
    y += 22
    rl.GuiSliderBar(
        {panel_x + 10, y, UI_WIDTH - 40, 20},
        "0", "1",
        &ui.drive_value, 0, 1,
    )
    if rl.GuiButton({panel_x + 10, y + 26, 120, 24}, "Set Drive") {
        set_drive(brain, Drive(ui.selected_drive), ui.drive_value)
    }
    y += 60

    // Source / Noun
    rl.GuiLabel({panel_x + 10, y, 200, 20}, "Source (object)")
    y += 22
    rl.GuiSliderBar({panel_x + 10, y, UI_WIDTH - 40, 20}, "0", "1", &ui.source_value, 0, 1)
    if rl.GuiButton({panel_x + 10, y + 26, 120, 24}, "Set Source") {
        set_source(brain, Noun(ui.selected_source), ui.source_value)
    }
    y += 60

    // General Sense
    rl.GuiLabel({panel_x + 10, y, 200, 20}, "General Sense")
    y += 22
    rl.GuiSliderBar({panel_x + 10, y, UI_WIDTH - 40, 20}, "0", "1", &ui.sense_value, 0, 1)
    if rl.GuiButton({panel_x + 10, y + 26, 120, 24}, "Set Sense") {
        set_general_sense(brain, GeneralSense(ui.selected_sense), ui.sense_value)
    }
    y += 70

    // Tick / Learn buttons
    if rl.GuiButton({panel_x + 10, y, 130, 30}, "Tick") {
        tick(brain)
    }
    if rl.GuiButton({panel_x + 150, y, 130, 30}, "Tick + Learn") {
        tick_and_learn(brain)
    }
    y += 50

    // Dendrite list
    rl.GuiLabel({panel_x + 10, y, 280, 20}, "Dendrites (select to draw)")
    y += 24

    /*
    list_height := f32(rl.GetScreenHeight()) - y - 40
    rl.GuiListView(
        {panel_x + 10, y, UI_WIDTH - 30, list_height},
        labels_joined,           // "item1;item2;item3"
        &ui.scroll_index,
        &ui.selected_dendrite,
    )
    */
}