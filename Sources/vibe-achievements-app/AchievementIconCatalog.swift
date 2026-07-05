import Foundation

enum AchievementIconCatalog {
    static let fallbackSymbolName = "sparkles"

    static func symbolName(for achievementID: String) -> String {
        symbolNamesByAchievementID[achievementID] ?? fallbackSymbolName
    }

    private static let symbolNamesByAchievementID: [String: String] = [
        "achievement_unlocked_unlocking_achievement": "seal",
        "local_legend": "house",
        "the_vibes_compiled": "hammer",
        "prompt_it_into_existence": "wand.and.stars",
        "weekend_mvp_energy": "calendar",
        "readme_driven_development": "doc.text",
        "the_first_big_door": "door.left.hand.open",
        "side_quest_accepted": "figure.walk",
        "main_quest_never_heard_of_her": "map",
        "keeper_of_small_fires": "flame",
        "one_more_prompt": "text.bubble",
        "actually_wait": "arrow.triangle.2.circlepath",
        "the_message_had_mass": "scalemass",
        "confidence_high_context_low": "battery.25",
        "context_window_sunset": "sunset",
        "token_budget_lifestyle": "creditcard",
        "the_app_has_opinions": "exclamationmark.triangle",
        "lore_drop": "scroll",
        "stack_trace_oracle": "terminal",
        "the_bug_has_a_shape_now": "questionmark.circle",
        "one_more_run": "arrow.clockwise",
        "green_bar_acquired": "checkmark.rectangle.stack",
        "green_by_coincidence": "dice",
        "understanding_optional": "questionmark.diamond",
        "we_are_so_back": "arrow.up.circle",
        "its_so_over": "arrow.down.circle",
        "rubber_duck_with_a_gpu": "brain.head.profile",
        "the_fix_was_elsewhere": "arrow.left.and.right",
        "it_works_therefore_it_is": "checkmark.circle",
        "nobody_touch_it": "hand.raised",
        "ship_it_before_it_notices": "paperplane",
        "lgtm_from_the_void": "eye",
        "the_diff_looked_friendly": "doc.text.magnifyingglass",
        "production_is_a_place": "shippingbox",
        "the_button_exists_now": "button.programmable",
        "css_negotiations": "paintbrush",
        "cache_clearing_ritual": "arrow.counterclockwise",
        "rm_rf": "trash.slash",
        "multiclassing": "person.2",
        "party_finder": "person.3",
        "changed_lanes": "arrow.left.arrow.right",
        "co_op_campaign": "rectangle.3.group",
        "the_council_has_convened": "person.3.sequence",
        "two_opinions_enter": "quote.bubble",
        "model_diplomat": "scale.3d",
        "same_quest_different_campfire": "arrow.turn.up.left",
        "shipwright": "hammer",
        "again_but_different": "arrow.triangle.branch",
        "found_your_way_back": "clock.arrow.circlepath",
        "platinum_memory": "trophy"
    ]
}
