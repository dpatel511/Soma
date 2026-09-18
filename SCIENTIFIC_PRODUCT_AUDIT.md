# Soma Health, Science, and Product Audit

Date: 2026-09-15

## Scope and standard

This audit reviews Soma as a consumer wellness application, not as a medical device. It compares the implemented HealthKit pipeline and formulas with peer-reviewed evidence, Apple validation material, and WHOOP's current public product behavior. A feature can be useful without being scientifically validated; the product must label that distinction honestly.

Ratings used below:

- **Supported input**: the underlying measurement or relationship has reasonable evidence.
- **Plausible heuristic**: directionally sensible, but Soma's exact formula, weights, or thresholds have not been validated.
- **Unsupported claim**: the UI or copy promises more than the implementation or evidence establishes.
- **Safety-sensitive**: wording could be interpreted as diagnosis or medical advice.

## Executive conclusion

Soma has a solid privacy-first architecture and a credible set of Apple Health inputs. It is not yet scientifically defensible as an "open-source WHOOP" if that phrase implies equivalent algorithms or validation. The core scores are transparent, hand-authored heuristics. That is acceptable for a wellness app if the app exposes confidence, missing-data state, provenance, and limitations instead of presenting every score as a precise physiological fact.

The recommended product position is:

> A local-first Apple Health interpretation and coaching app with transparent, community-auditable wellness heuristics.

Do not claim WHOOP-equivalent accuracy, medical interpretation, causal behavior insights, or validated biological age until those claims have supporting validation studies.

## Health feature audit

| Feature | Current implementation | Assessment | Required change |
|---|---|---|---|
| HRV baseline | Apple Health SDNN, arithmetic baseline plus log-domain EWMA/z-score | **Supported input; plausible scoring** | Make measurement timing/source visible. Avoid treating daytime SDNN and overnight SDNN as interchangeable. Validate the mapping from z-score to 0–100. |
| Resting heart rate | Difference from 30-day personal baseline | **Supported input; plausible scoring** | Show baseline and delta. Do not imply that a single deviation establishes readiness or illness. |
| Recovery | 40% HRV, 25% RHR, 25% sleep, 10% previous strain | **Plausible heuristic** | Validate the formula. Version 3 compares sleep-window median SDNN with prior sleep-window observations, prevents look-ahead during backfill, and leaves overnight HRV unavailable rather than substituting daytime HRV. The weights remain unvalidated. |
| Cardiovascular strain | Zone-minutes with custom convex weights, capped sampling intervals, mapped through a saturating curve against 14-day mean load | **Plausible heuristic** | Version 2 preserves headroom above an average-load day and stores HR data coverage. It still needs calibration against duration/intensity data. |
| Workout attribution | HR-pair midpoint inside HealthKit workout windows | **Reasonable engineering approximation** | Mark boundary attribution as approximate and test overlapping/adjacent workouts. Strength work is underrepresented because HR alone misses muscular load. |
| Sleep duration/timing | Apple Health sleep samples and naps | **Supported for consumer trend use** | Treat duration/timing as estimates, particularly when sources overlap. Surface source and completeness. |
| Sleep stages | Deep/REM/Core ratios contribute 10% of sleep score | **Appropriately limited but still heuristic** | Keep stages as context and validate the full score. Version 2 emphasizes duration and efficiency. |
| Sleep need | Baseline goal + three-night average shortfall + up to 30 minutes from strain | **Plausible heuristic** | Rename to "suggested sleep opportunity" or clearly label as an estimate. The exact debt forgiveness and strain addition are product choices, not validated physiology. |
| Sleep interruptions | Every detected awake segment costs 15 points | **Unsupported exact penalty** | Use awake time/efficiency and a personal baseline; wearable wake detection is noisy. Do not treat all segments equally. |
| Stress | Daytime HRV suppression and sedentary HR elevation | **Unsupported as a validated stress measure** | Rename to "physiological stress estimate." Version 2 removes the meditation deduction and exposes input coverage; validation is still required. |
| Evening stress | HR elevation alone | **Weak proxy** | Label as elevated evening heart rate, not autonomic stress, unless validated with movement/context controls. |
| Movement score | Stand hours, steps, and absolute walking HR | **Plausible heuristic with confounding** | Remove or personalize the absolute 60–120 bpm walking-HR mapping; pace, grade, age, medication, fitness, and environment strongly affect it. |
| Training guidance | Composite readiness, VO2-max multiplier, fatigue flags, and descriptive recent/chronic load ratio | **Plausible coaching; not validated prescription** | Version 2 removes automatic ACR penalties/caps and uses conditional language. Add user goals and sport context. |
| Behavior insights | Difference in next-day group means after at least five observations per group | **Exploratory association only** | Rename "correlations" to "observed associations." Add uncertainty, minimum paired coverage, confounder warnings, and multiple-testing control. Five observations per group is too weak for confident personalized claims. |
| Soma Age | Hand-tuned sum of year offsets from VO2 max, HRV, RHR, sleep, activity, and consistency | **Not scientifically validated** | Rename to "Soma Health Trend" until externally validated. Never say a weekly change means the user became years biologically younger/older. Preserve the breakdown as a wellness trend index. |
| Ayurvedic Sleep | Time-window points labelled as circadian alignment | **Cultural/wellness heuristic** | Clearly separate Ayurveda-inspired guidance from evidence-based sleep science. Do not present the score as physiological validation of circadian alignment. |
| Illness arc | Wrist-temperature deviation >0.5 C for two nights | **Safety-sensitive heuristic** | Rename to "temperature trend" and avoid illness detection language. Temperature changes have many causes; provide a non-diagnostic disclaimer and source completeness. |
| SpO2 alerts | A single daily value below 92% is called "critically low" | **Safety-sensitive and context-poor** | Do not diagnose from a single consumer wearable aggregate. Advise rechecking and following Apple/clinical guidance; distinguish persistent readings and symptoms. Emergency wording needs clinician-reviewed policy. |
| Menstrual adjustment | Fixed phase inference and up to six recovery points, currently disconnected | **Not ready** | Keep disabled. Future support should not assume a regular cycle or mechanically hide genuine physiological changes. Use inclusive onboarding and uncertainty-aware predictions. |

## Specific scientific problems

### 1. Recovery output is more certain than its evidence

HRV is useful for longitudinal monitoring, but it is not a direct scalar measurement of recovery. Meta-analyses find that autonomic markers can move with positive adaptation and overreaching, and HRV-guided training advantages are limited or inconsistent. Soma's personal log-domain normalization is a reasonable design direction, but the exact 40/25/25/10 weights and score bands are not validated.

Required product behavior:

- Display the underlying HRV, RHR, sleep, and load deviations alongside the score.
- Provide a confidence state based on data completeness and baseline length.
- Say "signals suggest" rather than "your body is recovered" or "primed."
- Version the formula so historical scores remain interpretable after changes.

### 2. Strain normalization had a mathematical product problem (addressed in version 2)

The original score was `today load / rolling average load * 100`, capped at 100. Once calibrated, a day equal to the user's recent average scored 100 and every above-average day also scored 100. Version 2 replaces this with `100 × (1 − exp(−load / capacity))`, so a capacity-level day is about 63 and harder days retain headroom.

The gap cap also systematically discards unsampled time. It prevents false inflation but can undercount sustained activity when Apple Watch sampling is sparse. This tradeoff needs coverage reporting rather than being invisible.

Recommended direction:

- Retain raw zone load.
- Introduce a separately calibrated, monotonic daily strain scale.
- Show recorded HR coverage and workout duration.
- Keep the score at 0–100 if desired, but do not market it as WHOOP's 0–21 Strain. WHOOP publicly states that its strain scale is nonlinear and 0–21.

### 3. Sleep stages should not dominate the score (addressed in version 2)

The original formula gave stage composition 30% of sleep score and used fixed targets. Independent wearable validation found much better sleep/wake agreement than multi-stage agreement; one study reported 53% multi-state agreement for Apple Watch Series 6. Apple's own validation material also identifies polysomnography as the reference standard. Version 2 reduces stage weight to 10% and adds sleep efficiency, but stage percentages remain estimates rather than precise targets to optimize.

Recommended weighting hierarchy:

1. Sleep opportunity/duration relative to the user's goal.
2. Timing consistency and sleep efficiency.
3. Personal overnight HR/RHR/HRV trends.
4. Stage composition as low-weight context, with no punitive one-night interpretation.

### 4. Logged mindfulness must not change a sensor-derived stress measurement (addressed in version 2)

The original `StressCalculator` subtracted up to five points when mindfulness minutes were present. Version 2 removes that deduction, keeping logged behavior separate from the sensor-derived estimate.

### 5. ACR should not be an injury or overtraining oracle (addressed in version 2)

The original implementation applied recovery penalties and capped training guidance when acute-to-chronic ratio exceeded 1.3. The simple rolling-ratio model has substantial methodological criticism and cannot establish an individual's injury or overtraining risk. Version 2 retains the ratio only as descriptive recent-versus-long-term load context.

### 6. Soma Age is a wellness index, not biological age

The implementation converts handcrafted offsets directly into years and can tell users they became fractions of a year younger or older within a week. The coefficients have not been trained or validated against morbidity, mortality, physiological age, or a held-out cohort. VO2 max is strongly relevant to health, but that does not validate adding the present sleep, HRV, steps, strain, and consistency offsets as years.

Safest replacement:

- Name: **Soma Health Trend** or **Healthspan Trend**.
- Output: improving/stable/declining plus a 0–100 index.
- Retain transparent drivers and opportunities.
- Do not express results in years until a documented model has external validation and subgroup calibration.

## WHOOP product comparison

WHOOP's current public platform centers on Sleep, Strain, Recovery, Stress, behaviors/journal insights, coaching, Health Monitor, Healthspan/Pace of Aging, cardiovascular plus muscular load, and—on some plans—regulated ECG/IHRN and blood-pressure insights. Soma covers much of the software surface using Apple Health, but it does not have WHOOP's continuous proprietary sensor stream, muscular-load model, validation corpus, or regulated features.

| Product area | Soma today | Gap from WHOOP-like experience |
|---|---|---|
| Daily home | Large readiness hero plus many cards/signals | Visually close, but too many competing scores. One daily state and one next action should dominate. |
| Recovery | Transparent composite | Good explainability; needs confidence, baseline deviation, and uncertainty. |
| Strain | Daily retrospective score and targets | Needs live progress/coverage and a stable nonlinear scale. HR-only load misses strength/muscular strain. |
| Sleep | Score, stages, need, debt, bedtime | Strong breadth; simplify the hierarchy and reduce stage precision. Add explicit sleep performance/efficiency. |
| Journal/check-in | Eight behaviors | Good foundation; WHOOP-like value comes from richer behavior selection and careful association statistics. |
| Coach | Rule-based suggestions | Useful offline differentiator. Copy is currently overconfident and repetitive; prioritize one recommendation with evidence/context. |
| Trends | Multiple charts and ranges | Needs more baseline-relative views, annotations, and behavior overlays instead of isolated lines. |
| Health monitor | Vitals and alerts | Needs a concise normal-range/baseline card and safe escalation language. |
| Healthspan | Soma Age | Similar concept, but current formula lacks validation and should not use years. |
| Women's health | Calculator exists but disabled | Product currently excludes women. A future implementation requires inclusive design and uncertainty, not a fixed add-back. |
| Hardware advantages | Uses Apple Watch/HealthKit | Cannot promise 24/7 raw sampling, identical HRV timing, muscular load, haptic sleep coaching, or WHOOP-equivalent algorithms. |

## UI audit

### What already works

- Dark canvas, high-contrast typography, score colors, rings, gradients, and compact metric cards create an appropriate performance-product visual language.
- Reusable design tokens and components are centralized rather than duplicated.
- The readiness hero gives the home screen a clear visual anchor.
- Detail screens, trends, coaching, and daily check-ins cover the expected interaction loop.

### What needs improvement

1. **Reduce score proliferation.** Recovery, readiness, stress, movement, strain, sleep, Ayurvedic sleep, and Soma Age compete for authority. Define one primary daily recommendation, three core pillars, then treat the rest as supporting signals.
2. **Separate measurement from advice.** A metric card should show what was observed; a coaching card should show what Soma recommends. Do not mutate measurements to reward behaviors.
3. **Design missing data explicitly.** Neutral 50s can look like real measurements. Use unavailable, partial, and calibrating states with coverage details.
4. **Make personal baseline the visual reference.** Raw values and deviation from baseline are more trustworthy than unexplained red/yellow/green bands.
5. **Use progressive disclosure.** Home should answer: How am I today? What caused it? What should I do? Detailed physiology belongs one tap deeper.
6. **Tighten navigation.** Organize around Today, Plan/Coach, Trends, and Profile/Settings. Avoid separate destinations that repeat the same metrics.
7. **Improve accessibility.** State cannot rely on green/yellow/red alone. Every colored state needs text/icon semantics, Dynamic Type checks, Reduce Motion behavior, and contrast verification.
8. **Avoid copying WHOOP trade dress.** Borrow the interaction model—daily state, causal explanation, next action—not proprietary wording, exact visual composition, or branded scale behavior.

## Recommended home hierarchy

1. **Today:** one readiness/recovery state with confidence and last-sync time.
2. **Plan:** target effort range plus one primary action.
3. **Three pillars:** Recovery, Strain, Sleep with short baseline-relative explanations.
4. **Key signals:** HRV, RHR, sleep duration/efficiency, respiratory rate, temperature trend.
5. **Journal prompt:** quick completion and an explanation of why more observations improve insights.
6. **Alerts:** only actionable, safety-reviewed exceptions.

## Copy changes required before wider release

Replace categorical physiological claims with calibrated language:

| Current style | Safer style |
|---|---|
| "Your body is recovered." | "Your recent signals are near or above your baseline." |
| "will reverse the trend" | "may help improve aerobic fitness over time." |
| "lowers cortisol and improves HRV" | "may help you wind down; watch your own trend." |
| "critically low" from one SpO2 value | "lower than your usual range; recheck and seek medical guidance if persistent or accompanied by symptoms." |
| "overtraining risk" from ACR | "recent load is higher than your longer-term average." |
| "Soma Age dropped by 1.2 years this week" | "Your long-term health trend improved, led by ..." |
| "correlation" from a mean difference | "observed association in your logged days." |

## Engineering and release blockers found during the audit

- No `LICENSE` file: the repository is source-visible, not legally open source.
- Widget deployment target is iOS 26.2 while the app target and documentation say iOS 17.
- Widget code uses `group.com.prasjain.Soma`, but the widget target has no configured entitlements file in the project settings.
- Widget setup documentation says the target still needs to be created even though it already exists.
- README says alcohol/caffeine can be written to HealthKit, while the implementation requests no write types and performs no write.
- No macOS CI workflow is present for build and XCTest verification.

## Implementation order

### P0 — honesty and safety

1. Add a wellness/non-diagnostic disclaimer at onboarding, settings, and safety-sensitive insights.
2. Remove deterministic medical, causal, and overtraining language.
3. Rename Soma Age and illness detection unless supporting validation is produced.
4. Introduce explicit unavailable/partial/calibrating states; never substitute a displayed neutral score for absent data.

### P1 — metric integrity

- **Implemented locally; CI pending (version 3):** Recovery HRV now uses a median of finite positive sleep-window SDNN samples, matches that value to prior sleep-window history, excludes the target/future days from backfilled baselines, and does not replace missing overnight HRV with daytime values.

Implemented in score algorithm version 2:

1. Strain uses a monotonic saturating curve; a personal-capacity day maps to about 63 rather than 100.
2. Logged mindfulness no longer changes sensor-derived stress.
3. Sleep stage composition is reduced from 30% to 10%; duration and efficiency now dominate.
4. ACR penalties and training caps are removed; recent/chronic load remains descriptive context.
5. Daily records persist the formula version, weighted input coverage, and low/medium/high confidence for each core score. Low-coverage scores are hidden on primary dashboard tiles.

### P2 — WHOOP-like product loop

1. **Implemented and CI-verified:** Today now prioritizes state, explanation, and the daily plan before supporting scores.
2. **Implemented and CI-verified:** HRV, resting HR, sleep duration, and wrist temperature are shown relative to personal data; comparisons calibrate until seven prior observations exist.
3. **Implemented and CI-verified:** Behavior insights now show both group sizes, an approximate 95% interval, exploratory labeling, and confounder-aware association wording. Multiple-testing control remains future work.
4. **Implemented locally; CI pending:** Workout summaries now report heart-rate sample coverage, retain logged workouts when HR data is missing, and explicitly describe strain as an Apple Health snapshot rather than a live measurement. HR-only muscular-load limitations remain visible.

### P3 — open-source readiness

1. Choose and add a license.
2. Fix widget target/entitlements and reconcile documentation.
3. Add macOS CI for build and tests.
4. Add algorithm documentation with evidence level, formula version, limitations, and test vectors.

## Evidence reviewed

- WHOOP, How WHOOP Works: https://www.whoop.com/us/en/how-it-works/
- WHOOP Support, WHOOP Basics and 0–21 nonlinear Strain: https://support.whoop.com/s/article/WHOOP-Basics
- WHOOP Support, Recovery: https://support.whoop.com/s/article/WHOOP-Recovery
- WHOOP Support, Membership Features: https://support.whoop.com/s/article/Membership-Features-Benefits
- Apple, Estimating Sleep Stages from Apple Watch: https://www.apple.com/healthcare/docs/site/Estimating_Sleep_Stages_from_Apple_Watch_Sept_2023.pdf
- Miller et al. (2022), validation of six wearables against PSG/ECG: https://pubmed.ncbi.nlm.nih.gov/36016077/
- Lee et al. (2024), commercial wearable sleep validation against PSG: https://pubmed.ncbi.nlm.nih.gov/39460013/
- Bellenger et al. (2016), autonomic HR regulation and training status meta-analysis: https://pubmed.ncbi.nlm.nih.gov/26888648/
- Manresa-Rocamora et al. (2021), HRV-guided training meta-analysis: https://pubmed.ncbi.nlm.nih.gov/34639599/
- Düking et al. (2020), data-guided versus predefined training review: https://pubmed.ncbi.nlm.nih.gov/32785959/

## Validation boundary

This was a code, product, and literature audit. No claim here establishes clinical validity. XCTest runs in macOS CI; device behavior was not executed because the current host is Windows and does not provide Xcode, the iOS simulator, HealthKit, or WidgetKit runtime verification.
