package main

import "../biv"
import rl "vendor:raylib"
import "core:fmt"

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE})
    rl.InitWindow(1400, 900, "BIV – Brain In a Vat")
    rl.SetTargetFPS(60)

    brain := biv.create()
    defer biv.destroy(brain)

    ui: biv.UI_State
    ui.selected_dendrite = -1
    biv.build_dendrite_list(brain, &ui)

    biv.update_layout(biv.GRID_PAD, biv.GRID_PAD)

    for !rl.WindowShouldClose() {

        if rl.IsKeyPressed(.SPACE) do biv.tick(brain)

        rl.BeginDrawing()
        rl.ClearBackground({15, 15, 25, 255})

        to_draw: []biv.Dendrite_Ref
        if ui.selected_dendrite >= 0 && ui.selected_dendrite < len(ui.dendrite_list) {
            to_draw = ui.dendrite_list[ui.selected_dendrite:ui.selected_dendrite+1]
        } else if ui.show_all_dendrites {
            to_draw = ui.dendrite_list[:]
        }

        biv.draw_brain(brain, to_draw)
        biv.draw_ui(brain, &ui)

        // Status line
        decision  := biv.get_decision(brain)
        attention := biv.get_attention(brain)
        rl.DrawText(
            fmt.ctprintf("Decision: %v   Attention: %v   Tick: %d", decision, attention, brain.tick),
            10, rl.GetScreenHeight() - 28, 18, rl.RAYWHITE,
        )

        rl.EndDrawing()
    }

    rl.CloseWindow()

    /*
    brain := biv.create()
    defer biv.destroy(brain)

    // Scenario: creature is hungry, sees food, decides to “push” (eat)
    for trial in 0..<100 {
        // Sensory situation
        biv.set_drive(brain, .Hunger, 0.9)           // Hunger high
        biv.set_source(brain, .Food, 0.8)            // Food present
        biv.set_general_sense(brain, .ItNearMe, 0.7) // near me

        biv.speak_verb(brain, .Push)
        biv.speak_noun(brain, .Food)

        biv.tick(brain)

        decision  := biv.get_decision(brain)
        attention := biv.get_attention(brain)

        // Simple external critic:
        // If it chose “Push” (1) while attending to Food (6) → reward
        // Otherwise mild punishment
        if decision == .Push && attention == .Food {
            biv.set_reward(brain, 0.7)
            biv.set_punish(brain, 0.0)
            fmt.printf("Trial %2d: GOOD  (Push food)  reward\n", trial)
        } else {
            biv.set_reward(brain, 0.0)
            biv.set_punish(brain, 0.25)
            fmt.printf("Trial %2d: decision=%v attn=%v  punish\n", trial, decision, attention)
        }

        biv.learn(brain)
    }
    */
}