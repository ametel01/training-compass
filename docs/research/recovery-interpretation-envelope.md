# Recovery interpretation envelope

Research current as of 2026-08-12. This note synthesizes primary research,
professional-society guidance, first-party Apple documentation, and current FDA
general-wellness guidance. It establishes a conservative product-language
boundary, not a medical or legal determination.

## Decision

Training Compass may describe how recorded sleep duration and consistency,
resting heart rate, and HealthKit HRV SDNN compare with the user's preceding
28-day Personal Recovery Baseline. It may then invite the user to consider those
measurements alongside how they feel and what they know about their circumstances
before a planned session.

It must not call a value normal or abnormal, diagnose a cause, label the user
recovered or unrecovered, estimate injury or illness risk, or prescribe a change
to training. No individual signal, sign-based vote, or transparent arithmetic
combination of these signals is validated for those stronger claims in this
product's population, sensor context, and 5/3/1 use case. Sports-medicine
consensus finds no single generally accepted marker of overtraining and no single
load-response marker that consistently predicts acute illness or overtraining
syndrome. ([ECSS/ACSM consensus](https://pubmed.ncbi.nlm.nih.gov/23247672/),
[IOC consensus](https://bjsm.bmj.com/content/50/17/1043))

The accepted minimum of two primary signals with established baselines is
therefore a **presentation guardrail**, not a validated readiness classifier. It
permits a cautious cross-signal summary while every measurement remains visible
and independently qualified. It does not increase the permissible strength of a
claim.

## The baseline is descriptive, not diagnostic

The Personal Recovery Baseline's median and 25th-to-75th-percentile band are
robust descriptive summaries. The interquartile band contains the middle 50% of
the reference observations, so values outside it are expected by construction;
crossing its edge is not an anomaly threshold. The UI may say “above/below your
recent middle half,” but not “unusual,” “outlier,” “warning,” “normal,” or
“abnormal” on that basis alone. ([NIST box-plot definition](https://itl.nist.gov/div898/handbook/eda/section3/boxplot.htm),
[NIST measures of scale](https://www.itl.nist.gov/div898/handbook/eda/section3/eda356.htm))

The 14-valid-day minimum reduces the chance that a very sparse reference is
presented as settled, but it is a product rule rather than a clinically validated
sample-size threshold. The band answers only “where is this recorded value
relative to this person's recent recorded values?” It cannot answer whether the
value is healthy, sufficient, caused by training, or predictive of today's
performance.

Every comparison must use the same documented daily-reduction rule and, as far
as HealthKit permits, comparable source and measurement context. A source or
algorithm change, a late correction, or a day with sparse samples must remain
visible. Apple documents that HealthKit HRV is specifically SDNN, that Apple Watch
records samples automatically, and that an algorithm-version metadata key may be
present; Apple also warns that occasional heart-rate values can be anomalously
high or low and that reliable readings are not always possible. ([HealthKit HRV
SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn),
[Apple Watch heart-rate measurement](https://support.apple.com/en-us/120277))

## What each signal can support

### Sleep duration and consistency

Allowed interpretation:

- State the recorded duration, its difference from the baseline median, and its
  position relative to the middle-half band.
- Describe duration consistency and sleep-midpoint consistency as more or less
  variable than the user's own recent record, using the actual app-defined
  statistic and window.
- Say that sleep is one factor the user may wish to consider alongside how they
  feel.

The American Academy of Sleep Medicine and Sleep Research Society recommend that
adults aged 18–60 generally sleep at least seven hours regularly, while explicitly
recognizing that individual sleep need varies with genetic, behavioral, medical,
and environmental factors. That population recommendation means a personal
baseline is not a measure of sleep sufficiency: sleep can be typical for the user
and still fall below general guidance, or differ from the baseline for benign
reasons. Training Compass's accepted product policy avoids applying a population
threshold, so it should not imply “enough sleep” from baseline membership.
([AASM/SRS consensus statement](https://aasm.org/resources/pdf/pressroom/adult-sleep-duration-consensus.pdf))

Objective sleep regularity has prospective associations with long-term health
outcomes, but the cited cohort work measured a multi-day Sleep Regularity Index
and observed associations in large, older populations. It did not validate a
single irregular night, this app's duration/midpoint variability measures, or an
acute strength-training readiness decision. The app may describe recorded
regularity; it may not convert it into a claim about today's recovery, future
disease, or causal benefit. ([Windred et al., 2024](https://pubmed.ncbi.nlm.nih.gov/37738616/),
[Chung et al., 2024](https://pubmed.ncbi.nlm.nih.gov/37752591/))

HealthKit sleep is a source-dependent category-sample timeline. Apple documents
that detailed samples can be absent at the beginning or end of an in-bed period,
and Apple describes Watch sleep stages as estimates. In a one-night laboratory
study of 53 healthy adults, Apple Watch Series 6 sleep/wake agreement with
polysomnography was 88%, but Cohen's kappa was only 0.30. Consequently, the app
must use “recorded” or “estimated,” preserve source and coverage, and keep sleep
stages descriptive rather than treating them as recovery evidence. ([HealthKit
sleep-analysis values](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis),
[Apple Watch sleep guide](https://support.apple.com/guide/watch/track-your-sleep-apd830528336/watchos),
[Miller et al., 2022](https://pubmed.ncbi.nlm.nih.gov/36016077/))

### Resting heart rate

Allowed interpretation:

- State the recorded beats per minute, difference from baseline median, and
  position relative to the middle-half band.
- Say that the measurement is higher or lower than the user's recent record.
- Invite the user to consider known context such as recent activity, temperature,
  emotion, pain, or medication without asserting that any one caused the change.

Personal comparison is reasonable because a two-year wearable cohort of 92,457
adults found wide between-person differences in mean resting heart rate and
smaller but real within-person variation. The study had no clinical data with
which to assign causes to individual episodes, so it supports longitudinal
description, not diagnosis. ([Quer et al., 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7001906/))

A resting-heart-rate change is nonspecific. The American Heart Association lists
temperature, body position, exercise, emotions, pain, body size, and medication
among influences, and notes that a low rate is common in athletes and during
sleep. The app therefore must not translate “higher than baseline” into illness,
stress, poor recovery, or overtraining, nor “lower” into improved fitness or good
recovery. ([American Heart Association](https://www.heart.org/en/health-topics/high-blood-pressure/the-facts-about-high-blood-pressure/all-about-heart-rate-pulse))

### Heart-rate variability SDNN

Allowed interpretation:

- Name the metric as **HRV SDNN**, show milliseconds, source, sample count, latest
  included sample, daily reduction, and relation to the personal baseline.
- Say only that SDNN was higher or lower than the user's recent record.
- Treat a source or algorithm-version change, incomparable sampling context, or
  a single sparse sample as a limitation on interpretation.

SDNN is not interchangeable with other HRV metrics or recording protocols.
Professional standards warn that HRV's meaning is more complex than its easy
calculation suggests, that recording duration affects values, and that short- and
long-duration measurements require standardized, distinct interpretation.
HealthKit exposes SDNN; much athlete-readiness research instead uses RMSSD or
other vagal-related metrics under standardized morning or laboratory protocols.
Those algorithms and results cannot simply be transferred to opportunistic
HealthKit SDNN samples. ([ESC/NASPE standards](https://pubmed.ncbi.nlm.nih.gov/8598068/),
[HealthKit HRV SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn))

Apple Watch HRV can reflect controlled physiological changes, but validation is
narrower than a readiness claim. A study of 20 healthy volunteers found strong
agreement for time-domain HRV measures during controlled relaxation and mild
mental stress, while also finding gaps in the Watch RR series. A newer study of
78 healthy adults found the best agreement at rest but only moderate agreement
for normal-to-normal intervals. Neither study validated a daily recovery label or
5/3/1 training prescription. ([Hernando et al., 2018](https://pubmed.ncbi.nlm.nih.gov/30103376/),
[Validity of HRV measured with Apple Watch Series 6, 2025](https://pubmed.ncbi.nlm.nih.gov/40285070/))

Direction is not a reliable verdict. In trained endurance athletes, both positive
adaptation and functional overreaching have been accompanied by increased
vagal-related HRV measures, and an overload study found that isolated weekly HRV
values missed changes detected in weekly averages. These studies used metrics
and protocols unlike opportunistic HealthKit SDNN, but they directly refute the
simple semantics “higher HRV is always better” and “one low HRV value means poor
recovery.” ([Bellenger et al., 2021](https://pubmed.ncbi.nlm.nih.gov/33488402/),
[Le Meur et al., 2013](https://pubmed.ncbi.nlm.nih.gov/24136138/))

## Defensible combination rules

No reviewed primary or authoritative source validates a fixed score, weighted
formula, majority vote, or red/amber/green threshold that combines this app's
HealthKit sleep, resting-heart-rate, and SDNN inputs into recovery or training
readiness. Research models are study-, device-, population-, and outcome-specific;
in a 12-week study of 43 endurance athletes, individualized recovery-model error
varied widely between people. A model trained elsewhere would be opaque rather
than a transparent rule for this owner. ([Rothschild et al., 2024](https://pubmed.ncbi.nlm.nih.gov/38900201/))

Use this deterministic presentation policy instead:

| Evidence state | Permitted output |
| --- | --- |
| No established baseline | Show the available measurements and “baseline still forming”; produce no Recovery Guidance. |
| One primary signal with a baseline | Describe that signal only; say there is insufficient evidence for cross-signal guidance. |
| At least two primary signals with baselines | List every signal separately, with value, baseline comparison, source/coverage, and freshness; optionally add the neutral self-check prompt below. |
| Signals move in commonly opposed directions | Say “the measurements do not move together” and enumerate them; do not decide which wins. |
| Signals move together | Say “several measurements differ from your recent record” and enumerate them; do not call the pattern good, bad, recovered, strained, or predictive. |
| Any signal is missing, stale, corrected, or source-incomparable | Mark that limitation explicitly; never encode it as neutral or favorable. |

Sleep duration, duration consistency, and timing consistency share underlying
sleep episodes; they must not be presented as three independent votes. Resting
heart rate and HRV can also share device and physiological context. The product
may count signals to enforce the accepted minimum-evidence gate, but it must not
turn the count into confidence, severity, or a majority decision.

The only general prompt supported by this envelope is:

> Before today's planned session, consider how you feel and anything that may
> have influenced these measurements. You decide whether to keep or change the
> session.

That prompt intentionally does not recommend postponing, reducing, or changing a
session. If the user chooses a change, it enters the app through the existing
user-confirmed schedule or session controls, not through Recovery Guidance.

## Language contract

| Safe | Avoid |
| --- | --- |
| “Recorded sleep was below your recent median and below your recent middle half.” | “You did not recover,” “sleep debt,” or “you need more recovery.” |
| “Resting heart rate was 6 bpm above your recent median.” | “Your heart rate shows illness, stress, or overtraining.” |
| “HRV SDNN was below your recent middle half; Apple Health supplied one sample.” | “Your nervous system is strained,” “low readiness,” or “your HRV is abnormal.” |
| “The measurements do not move together: …” | “The good signals outweigh the bad,” a score, or a color verdict. |
| “Several measurements differ from your recent record: …” | “Multiple warning signs,” “poor recovery,” or a probability of injury/illness. |
| “There is not enough comparable evidence for guidance.” | Treating missing data as average, normal, or favorable. |
| “Consider how you feel before the session; you decide whether to keep or change it.” | “Reduce intensity,” “skip today,” “deload,” or any automatic program edit. |

Use “usual for you” only where nearby copy defines it as the preceding 28-day
median and middle-half band. Prefer the exact statistical wording in detail views.
Do not use “risk,” “detect,” “monitor for,” “warning,” “alert,” “healthy,” or
“optimal” for computed outputs.

The FDA's January 2026 general-wellness guidance provides a useful conservative
language boundary: software unrelated to diagnosis, cure, mitigation, prevention,
or treatment can remain general wellness, and an evaluation suggestion should
not name a disease, characterize output as abnormal/pathological/diagnostic, use
clinical thresholds, or recommend treatment. FDA also lists historical trending
and comparison of vital signs as a lower-risk function. These are regulatory
policy examples, not a determination of this app's status in any jurisdiction.
([FDA general-wellness guidance](https://www.fda.gov/media/90652/download),
[FDA lower-risk software examples](https://www.fda.gov/medical-devices/device-software-functions-including-mobile-medical-applications/examples-software-functions-which-fda-will-exercise-enforcement-discretion))

## Safety handoff

Recovery Guidance must not attempt symptom triage. A separate, static help entry
may repeat authoritative escalation guidance without making it a computed result:

- The American Heart Association advises contacting a health professional when
  heart rate is slower or faster than usual, especially with weakness, dizziness,
  or near-fainting, and calling emergency services for a suddenly very high or low
  rate accompanied by symptoms such as chest pain, shortness of breath, dizziness,
  or fainting. ([American Heart Association](https://www.heart.org/en/health-topics/high-blood-pressure/the-facts-about-high-blood-pressure/all-about-heart-rate-pulse))
- AASM/SRS guidance says people concerned that they sleep too little or too much
  should consult a healthcare provider. ([AASM/SRS consensus statement](https://aasm.org/resources/pdf/pressroom/adult-sleep-duration-consensus.pdf))

This help entry should be reachable but must not fire because a value crossed the
Personal Recovery Baseline band. The app has neither a clinical threshold nor the
validated context needed to trigger that conclusion.

## Requirements handed to later decisions

- Label all values as recorded or estimated evidence, with source, coverage,
  sample count, latest included sample, sync time, and any algorithm-version or
  source change available from HealthKit.
- Display the median and middle-half band as context, never as a target, normal
  range, anomaly detector, or pass/fail boundary.
- Show trend and snapshot separately; do not infer a trend from one daily value.
- Require the accepted minimum of two baselined primary signals before showing a
  cross-signal self-check prompt, while keeping every signal independently visible.
- Do not treat correlated sleep submetrics, missing data, or a signal count as
  votes or confidence.
- Use neutral enumeration for aligned and conflicting measurements; never output
  readiness, recovery, stress, illness, injury-risk, or training-effect labels.
- Never issue warning-style notifications or concrete session changes from these
  measurements. Reconciliation can revise the evidence, so visibly timestamp and
  recalculate it.
- Keep the static medical-help route separate from computed Recovery Guidance.

## Primary and authoritative sources

- [AASM/SRS recommended adult sleep duration consensus](https://aasm.org/resources/pdf/pressroom/adult-sleep-duration-consensus.pdf)
- [Windred et al.: sleep regularity and mortality](https://pubmed.ncbi.nlm.nih.gov/37738616/)
- [Chung et al.: objectively regular sleep patterns and mortality](https://pubmed.ncbi.nlm.nih.gov/37752591/)
- [Quer et al.: inter- and intraindividual resting-heart-rate variability](https://pmc.ncbi.nlm.nih.gov/articles/PMC7001906/)
- [ESC/NASPE heart-rate-variability standards](https://pubmed.ncbi.nlm.nih.gov/8598068/)
- [Hernando et al.: Apple Watch HRV validation](https://pubmed.ncbi.nlm.nih.gov/30103376/)
- [Miller et al.: validation of six wearables](https://pubmed.ncbi.nlm.nih.gov/36016077/)
- [Meeusen et al.: ECSS/ACSM overtraining consensus](https://pubmed.ncbi.nlm.nih.gov/23247672/)
- [Schwellnus et al.: IOC load and illness consensus](https://bjsm.bmj.com/content/50/17/1043)
- [Bellenger et al.: paradoxical HRV response in functional overreaching](https://pubmed.ncbi.nlm.nih.gov/33488402/)
- [Le Meur et al.: daily versus isolated HRV in functional overreaching](https://pubmed.ncbi.nlm.nih.gov/24136138/)
- [Apple HealthKit HRV SDNN documentation](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn)
- [Apple HealthKit sleep-analysis documentation](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)
- [FDA General Wellness: Policy for Low Risk Devices, January 2026](https://www.fda.gov/media/90652/download)
