package main

import "core:fmt"

import "../biv"

main :: proc() {
    brain := biv.create()
    defer biv.destroy(brain)

    fmt.println("Initial random brain created and wired.")

    // Scenario: creature is hungry, sees food, decides to “push” (eat)
    for trial in 0..<30 {
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
            fmt.printf("Trial %2d: decision=%d attn=%d  punish\n", trial, decision, attention)
        }

        biv.learn(brain)
    }

    fmt.println("\nLearning finished.")
}