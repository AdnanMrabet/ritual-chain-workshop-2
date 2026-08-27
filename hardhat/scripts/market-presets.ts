/** Comparator enum, matching RitualPredict.Comparator. */
export const COMPARATOR = {
  gt: 0,
  gte: 1,
  lt: 2,
  lte: 3,
} as const;

/** MarketState enum, matching RitualPredict.MarketState. */
export const MARKET_STATE = ["Commit", "Reveal", "Resolving", "Resolved", "Invalid"] as const;

/** Outcome enum, matching RitualPredict.Outcome. */
export const OUTCOME = ["Unresolved", "YES", "NO"] as const;

/**
 * The preset workshop market: short enough to demo end-to-end in a few minutes.
 * Mirrors DEMO_MARKET in web/src/lib/presets.ts.
 */
export const DEMO_MARKET = {
  question: "Will weekday metro arrivals exceed 60 before 09:00?",
  oracleUrl: "https://data.example.test/transit",
  jsonPath: ".arrivals",
  target: 60,
  comparator: "gte",
  commitSeconds: 120,
  revealSeconds: 90,
  resolveDelaySeconds: 60,
} as const;
