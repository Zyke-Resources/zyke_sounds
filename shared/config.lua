Config = Config or {}

-- Times are in milliseconds
-- 1000ms = 1 second
Config.Settings = {
    -- Shows debug markers for sound positions and logs loaded sound files.
    debug = false,

    -- How often clients update active sound volume by distance. Lower is smoother, higher is cheaper.
    -- Can drastically affect performance if changed too much, only change if you know what you're doing.
    volumeUpdateInterval = 100,

    -- Command players use to open the sound volume menu.
    commandName = "sounds",

    -- Client storage key for saved volume multipliers. Change only if you want to reset saved volumes.
    kvpKey = "zyke_sounds:volumeMultiplier",

    -- It is highly adviced to not touch any of the configs below, unless you truly know what you are doing
    -- and have an understanding of what each setting will do.
    -- If not, you might create instabilities.

    -- How often the server checks if players moved to another routing bucket for location sounds.
    routingBucketUpdateInterval = 1000,

    -- Fallback length for sounds when the real audio duration is not known yet.
    unknownSoundDurationMs = 300000,

    -- Longest sound duration the server will trust and cache from a client report.
    -- Probably don't touch, unless you're playing sounds longer than 10 min.
    maxCachedSoundDurationMs = 600000,

    -- Clients report how long sound files are. If a new report differs by more than this, it is ignored.
    soundDurationToleranceMs = 500,

    -- How often the server checks if players moved into or out of range of active location sounds.
    soundCullingUpdateInterval = 1000,

    -- Stops muted entity sounds if the entity/player leaves local scope for long enough.
    stateBagEntityStaleMs = 2500,

    -- How long stop payloads stay in state bags so scoped clients can receive fade/forceFull stop data.
    stateBagStopTtlMs = 2000,

    -- Number of temporary sync slots for quick entity sounds.
    -- Per entity (player), a group of people won't all contribute to the same pool.
    stateBagEmitSlots = 4,

    -- How long quick entity sound sync data stays available before cleanup. Higher can help slow clients, but keeps stale data longer.
    oneShotStateBagTtlMs = 10000,
}