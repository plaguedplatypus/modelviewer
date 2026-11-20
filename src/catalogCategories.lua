-- A group matches any of its literal prefixes, suffixes, substrings, or underscore-separated tokens.
return {
    Model = {
        {
            label = "Treasure Hunter",
            tokens = { "TRH", "TRH131", "TRH110", "TRH133",
                         "TRH132", "TRH140", "TRH119",  },
        },
        {
            label = "Inventory",
            tokens = { "INV" },
        },
        {
            label = "Chat Heads",
            tokens = { "CHAT", "CHATHEAD" },
        },
        {
            label = "Body Parts",
            prefixes = { 
                "WOMAN_ARMS_",
                "WOMAN_TORSO_",
                "WOMAN_TORSOEXTRA_",
                "WOMAN_LEGS_",
                "WOMAN_HANDS_",
                "WOMAN_FEET_",
                "WOMAN_HEAD_",
                "WOMAN_JAW_",
                "WOMAN_HEADEXTRA_",
                "MAN_ARMS_",
                "MAN_TORSO_",
                "MAN_TORSOEXTRA_",
                "MAN_LEGS_",
                "MAN_HANDS_",
                "MAN_FEET_",
                "MAN_HEAD_",
                "MAN_JAW_",
                "MAN_HEADEXTRA_",

            },
        },
        {
            label = "Worn Gear",
            suffixes = { 
                "_TORSO",
                "_LEGS",
                "_HELMET",
                "_HANDS",
                "_BOOTS",
            },
            tokens = { "NECKLACES", "HAT"},
        },
        {
            label = "Held Equipment",
            prefixes = { "HUMAN_WEAPONS_" },
        },
        {
            label = "QUESTS",
            prefixes = { "QUEST_" },
        },
    },
    Obj = {
        {
            label = "Player-owned house",
            prefixes = { "CONSTRUCTION_HOUSE_FURNITURE_" },
        },
    },
}
