# HealthKit capability envelope

Research current as of 2026-08-12. This note uses only Apple Developer documentation and clearly marks product inferences and undocumented guarantees.

## Decision

Training Compass can use HealthKit as an authorized, eventually reconciled source of all `HKWorkout` records available to the iPhone and of the agreed Recovery Evidence: sleep analysis, resting heart rate, and heart-rate variability (SDNN). It can also read workout-associated heart-rate, energy, distance, and route data when those samples exist and the user authorizes their types. It can write a completed 5/3/1 Session back as a traditional-strength `HKWorkout` summary.

HealthKit is not the app's canonical 5/3/1 database. The app must keep its Training Schedule, Training Maxes, sets, repetitions, loads, Plus Sets, and e1RM calculations in its local model. Apple exposes no documented first-class lifting-set, repetition, or load schema; that conclusion is an inference from the documented workout object model and activity types, not an explicit Apple statement.

“Rolling” therefore means:

1. reconcile on foreground activation;
2. accept background observer delivery as an additional wake-up path;
3. retrieve actual changes with per-type anchored queries;
4. retain HealthKit UUID and provenance for imported samples;
5. apply additions, replacements, and deletions idempotently; and
6. show data freshness rather than promise continuous or real-time updates.

## Supported read surface

### All Health Workouts

All workouts share one `HKWorkoutType`; each returned `HKWorkout` supplies an activity type, start and end dates, duration, source information, and any available workout statistics. Consequently, authorization for the workout type and an unfiltered workout query can cover every workout activity type present in the authorized HealthKit store rather than requiring a list of sports. ([`HKWorkoutType`](https://developer.apple.com/documentation/healthkit/hkworkouttype), [`HKWorkout`](https://developer.apple.com/documentation/healthkit/hkworkout))

HealthKit automatically synchronizes its separate iPhone and Apple Watch stores. This makes Watch-recorded workouts available to the iPhone after HealthKit syncs them, without a Training Compass Watch app. Apple documents the automatic synchronization but gives no completion-time guarantee, so a newly recorded Watch workout may arrive later. ([About the HealthKit framework](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework))

The initial read authorization set should be deliberately narrow:

- `HKWorkoutType.workoutType()` for Health Workouts;
- heart rate for workout intensity and time-in-zone calculations;
- active energy burned and the relevant walking/running, cycling, and swimming distance quantity types for workout summaries where available;
- sleep analysis, resting heart rate, and heart-rate variability SDNN for Recovery Evidence; and
- workout route only if the product actually displays or analyzes routes.

Apple documents heart rate, resting heart rate, and HRV SDNN as distinct quantity types. Its HRV type is specifically SDNN, normally measured in milliseconds; it must not be presented as a generic or interchangeable HRV method. ([Quantity type identifiers](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier), [heart-rate variability SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn))

Sleep is a category-sample timeline. Its values can describe in-bed, awake, unspecified asleep, core, deep, and REM intervals, including overlapping in-bed and staged samples. Apple warns that Watch samples may omit detailed intervals at the beginning or end of an in-bed interval. The app must aggregate the samples it actually receives and tolerate overlapping sources and incomplete staging. ([`HKCategoryValueSleepAnalysis`](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis), [sleep-analysis identifier](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/sleepanalysis))

Resting-heart-rate estimates are mutable: Apple Watch may delete an earlier current- or previous-day estimate and replace it with a better estimate as the day progresses. This is a concrete reason to process deletions and additions instead of treating Recovery Evidence as append-only. ([resting heart rate](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/restingheartrate))

### Workout-associated heart rate and other details

An `HKWorkout` is a summary and a relationship anchor for detail samples. Heart rate is represented by ordinary `HKQuantitySample` objects, not by a guaranteed intrinsic series on every workout. With read authorization for the quantity type, `HKQuery.predicateForObjects(from:)` can restrict a separate sample query to objects associated with a particular workout. The same pattern applies to distance and active-energy details, and `HKWorkout.statistics(for:)` can expose summary statistics computed from associated quantity samples. ([Adding samples to a workout](https://developer.apple.com/documentation/healthkit/adding-samples-to-a-workout), [`predicateForObjects(from:)`](https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects(from:)-5irg9), [`HKWorkout.statistics(for:)`](https://developer.apple.com/documentation/healthkit/hkworkout/statistics(for:)))

`HKHeartbeatSeriesSample` is a different beat-to-beat series type; it is not a workout’s ordinary heart-rate timeline. Training Compass should query associated heart-rate quantity samples and must not assume heartbeat-series availability. ([`HKHeartbeatSeriesSample`](https://developer.apple.com/documentation/healthkit/hkheartbeatseriessample))

Apple does not document that every workout source associates heart rate, energy, distance, or any other detailed metric. Absence is therefore a supported state. Attributing unassociated heart-rate samples merely because their timestamps overlap a workout would be a Training Compass heuristic, not a HealthKit relationship; the initial product should not do this silently.

### Workout routes

With read authorization for workouts and workout routes, an app can read a route associated with any workout. It first queries `HKWorkoutRoute` samples associated with the workout, then uses `HKWorkoutRouteQuery` to stream the underlying `CLLocation` values in batches. ([Reading route data](https://developer.apple.com/documentation/healthkit/reading-route-data), [`HKWorkoutRouteQuery`](https://developer.apple.com/documentation/healthkit/hkworkoutroutequery))

Routes are not atomic with workouts. Apple explicitly notes that a workout may exist before its route, and that route-processing software may later replace a route with a smoothed version. Apple recommends an anchored object query to track route additions and updates. Route data must therefore remain an optional, late-arriving child of a Health Workout, never a condition for importing the workout itself. ([Reading route data](https://developer.apple.com/documentation/healthkit/reading-route-data))

Apple documents stored route locations as accurate within 50 metres and potentially in need of additional smoothing. Training Compass should not infer precise path or interval performance from them without a separate product decision. ([Reading route data](https://developer.apple.com/documentation/healthkit/reading-route-data))

## Authorization and configuration

The app target must enable the HealthKit capability, which supplies the `com.apple.developer.healthkit` entitlement, and call `HKHealthStore.isHealthDataAvailable()` before other HealthKit operations. The Info configuration must include a truthful `NSHealthShareUsageDescription` for reading and `NSHealthUpdateUsageDescription` for writing. ([Setting up HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit), [HealthKit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit), [`NSHealthShareUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nshealthshareusagedescription), [`NSHealthUpdateUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nshealthupdateusagedescription))

Authorization is fine-grained and separate for reading and sharing each requested type. The user may later change any permission. Current HealthKit also permits a limited recent window rather than full-history read access; `getEarliestAuthorizedSampleDate` can positively identify that limited state. ([Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data))

HealthKit intentionally prevents an app from learning whether read access to a type was denied. A denied read returns only samples the app itself wrote, which can look identical to an empty data set; `authorizationStatus(for:)` reports the app’s permission to save/share the type, not its read permission. Training Compass must therefore describe missing or partial evidence as “unavailable” and offer a route to system settings, not claim that the user denied permission or that no data exists. ([Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [`HKAuthorizationStatus`](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus))

## Rolling observation and reconciliation

### Background observation is a signal, not the import

`HKObserverQuery` reports that matching samples were saved or deleted, but supplies no changed objects. Its handler must start a sample or anchored query to retrieve the changes. Observer queries work in the foreground by default. ([Executing observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries))

Background delivery requires the Boolean `com.apple.developer.healthkit.background-delivery` entitlement and a successful `enableBackgroundDelivery(for:frequency:)` registration for each observed type. The documented supported background-delivery inputs include characteristic, quantity, category, and workout types, but not correlation or series types. Thus workout, sleep, resting-heart-rate, and HRV changes can be wake-up signals; no equivalent background-delivery guarantee is documented for `HKWorkoutRoute`, which is a series type. Route reconciliation should occur when the app is active and whenever a relevant workout change prompts it. ([background-delivery entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit.background-delivery), [`enableBackgroundDelivery`](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)))

Apple says the requested update frequency is a maximum wake-up frequency, and defines `.immediate` as launching the app whenever the system detects a change. It publishes no wall-clock delivery SLA. Training Compass may request `.immediate`, but its product contract must be eventual refresh, not a guaranteed real-time feed. ([`HKUpdateFrequency`](https://developer.apple.com/documentation/healthkit/hkupdatefrequency), [`.immediate`](https://developer.apple.com/documentation/healthkit/hkupdatefrequency/immediate))

Observer queries intended for background delivery must be instantiated at launch, before HealthKit delivers pending changes. The handler must call its completion callback after reconciliation. If an app fails to respond three times, HealthKit stops background updates; the APIs are not supported in Simulator and require device testing. ([Executing observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries), [`enableBackgroundDelivery`](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)))

HealthKit reads can fail with `errorDatabaseInaccessible` while the device is locked, even though writes can temporarily queue for merging after unlock. The sync engine must preserve its prior anchor and retry later rather than advance state after such a failure. The retry/anchor rule is a product inference built on Apple’s documented lock behavior. ([`errorDatabaseInaccessible`](https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible))

Apple’s API documentation does not specify force-quit behavior. In an official Developer Forums answer, Apple Developer Technical Support states that HealthKit background delivery is not an exception to the general rule preventing relaunch after a user force-quits an app. This is an Apple staff statement, not an API contract; foreground reconciliation remains necessary. ([Apple Developer Forums: background delivery after force quit](https://developer.apple.com/forums/thread/775325))

### Anchored changes are the durable import mechanism

`HKAnchoredObjectQuery` returns newly saved samples, `HKDeletedObject` tombstones, and a new opaque anchor. Passing that anchor to a later query restricts results to changes after it; a `nil` anchor requests all currently matching samples and only recently retained deleted objects. Apple recommends bounded date ranges or batched anchored queries for large stores. ([`HKAnchoredObjectQuery`](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery), [anchor semantics](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquerydescriptor/anchor), [Running queries with Swift concurrency](https://developer.apple.com/documentation/healthkit/running-queries-with-swift-concurrency))

The app should keep an independent anchor for each queried sample type and predicate contract. This per-stream design is an inference: anchors describe a particular query’s change position, so sharing an anchor across unlike queries is not documented as valid.

For crash safety, process a batch and persist its local changes and returned anchor in the same local transaction; advance the anchor only after every addition and deletion in that batch is durable. This atomicity rule is an implementation inference, not a HealthKit guarantee.

`HKDeletedObject` exposes the deleted object’s UUID, but tombstones are temporary and HealthKit may remove them at any time. Apple says an observer query with background delivery plus an anchored query is needed to guarantee receiving deletion events as they occur. Because force-quit, permission, locked-device, or prolonged-install gaps can still interrupt the app, Training Compass should also support a user-initiated full reconciliation that compares a bounded current snapshot against its local HealthKit mirrors. ([`HKDeletedObject`](https://developer.apple.com/documentation/healthkit/hkdeletedobject))

## Identity, provenance, and correction semantics

Every retrieved `HKObject` has a UUID for that particular entry. HealthKit also assigns a `sourceRevision` after saving; it identifies the saving app or device and adds version, operating-system, and optional product-type information. The object’s `device` property supplies hardware details when available. Older objects may lack product type, so provenance fields must be nullable. ([About the HealthKit framework](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework), [`HKSourceRevision`](https://developer.apple.com/documentation/healthkit/hksourcerevision), [`HKObject.sourceRevision`](https://developer.apple.com/documentation/healthkit/hkobject/sourcerevision), [`HKSourceRevision.productType`](https://developer.apple.com/documentation/healthkit/hksourcerevision/producttype))

For an imported Health Workout, its HealthKit UUID is the authoritative local mirror key. Preserve source bundle identity and available source/device revision information for display and diagnostics. Source alone is not a deduplication key: the same source legitimately creates many workouts.

HealthKit objects are immutable, and an app can delete only objects it previously saved. Training Compass cannot edit or delete a workout owned by Apple or another source. If another source corrects data, the local mirror must follow the additions/deletions that HealthKit exposes. ([About the HealthKit framework](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework), [`deleteObjects(of:predicate:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/deleteobjects(of:predicate:withcompletion:)))

For app-authored 5/3/1 workout summaries, write a stable local session identifier into `HKMetadataKeySyncIdentifier` and an incrementing version into `HKMetadataKeySyncVersion`. HealthKit documents that a save with the same sync identifier and a greater version replaces the lower-version object. Retain the returned HealthKit UUID as well. This provides an explicit identity path for avoiding re-import duplicates and for later correction of the app’s own summary. ([`HKMetadataKeySyncIdentifier`](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier), [`HKMetadataKeySyncVersion`](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncversion))

## Writing completed 5/3/1 Sessions

HealthKit defines `.traditionalStrengthTraining` for strength exercises primarily using machines or free weights; this is the closest documented type for the agreed barbell 5/3/1 Sessions. `.functionalStrengthTraining` is defined for strength work primarily using free weights and body weight, but the activity taxonomy does not encode the user’s set and load prescription. ([traditional strength training](https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype/traditionalstrengthtraining), [`HKWorkoutActivityType`](https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype))

`HKWorkoutBuilder` can build a workout without a live workout session or other data source. The app begins collection with the actual session start, ends it with the actual finish, adds app metadata, then calls `finishWorkout` to create and save the workout. Apple requires `endCollection` before `finishWorkout`. A manual post-session write-back therefore does not require an Apple Watch app or a live `HKWorkoutSession`. ([`HKWorkoutBuilder`](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder), [`finishWorkout`](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/finishworkout(completion:)))

The HealthKit workout should contain only interoperable summary facts: traditional-strength activity, actual start/end/duration, source, and a stable sync identifier/version. Training Compass-specific lift names, set weights, completed reps, Training Max history, Plus Set status, and e1RM remain local. Custom metadata is technically supported, but Apple describes custom keys as app-specific extensions; they do not create an interoperable lifting schema. ([`HKWorkout`](https://developer.apple.com/documentation/healthkit/hkworkout), [HealthKit metadata keys](https://developer.apple.com/documentation/healthkit/metadata-keys))

Writing requires share authorization for `HKWorkoutType`. Before saving, check `authorizationStatus(for:)`; a denied or not-yet-determined share permission causes an explicit error. If write permission is unavailable, completing and retaining the 5/3/1 Session locally must still succeed, with write-back shown as pending or unavailable. ([Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [`HKHealthStore.save`](https://developer.apple.com/documentation/healthkit/hkhealthstore/save(_:withcompletion:)-6fmtg))

An iPhone workout object contributes its duration to the Exercise ring, and active-energy samples contribute to the Move ring. Training Compass should not invent energy samples for a manually logged strength session. The absence of an energy estimate is preferable to an unsupported value. ([`HKWorkout`](https://developer.apple.com/documentation/healthkit/hkworkout))

## Explicit non-guarantees

The product and technical specifications must not rely on any of the following:

- knowing whether read access was denied;
- full historical access rather than a limited recent window;
- a fixed background-delivery latency or delivery after force quit;
- reading HealthKit while the phone is locked;
- every Health Workout having heart-rate samples, energy, distance, statistics, or a route;
- a workout and its route arriving together;
- unassociated time-overlapping samples belonging to a workout;
- source/device fields being complete on older records;
- tombstones remaining indefinitely;
- editing or deleting another source’s objects;
- HealthKit representing 5/3/1 sets, reps, loads, Training Maxes, or e1RM; or
- Simulator tests proving background delivery.

Apple’s 2026 documentation also exposes workout-zone APIs, including completed-workout heart-rate zone groups, but the material is tied to beta OS releases and explicitly subject to change. The initial stable design should calculate zones from authorized associated heart-rate samples under an app-owned, explained zone policy; adopting Apple’s zone representation can be reconsidered when the deployment target and APIs are stable. ([HealthKit updates](https://developer.apple.com/documentation/updates/healthkit), [WWDC26: Deliver workout insights with HealthKit workout zones](https://developer.apple.com/videos/play/wwdc2026/207/))

## Requirements handed to later decisions

- Define sync UI states for never requested, locally empty or unreadable, limited history, fresh, stale, locked/retryable, and write-back denied or pending without claiming a hidden read-permission state.
- Persist per-stream anchors and HealthKit UUIDs locally; transactionally commit a batch before its new anchor.
- Reconcile workouts and each Recovery Evidence type at launch/foreground and after observer signals.
- Import the workout first; enrich heart rate, statistics, and route independently and idempotently.
- Preserve provenance and treat external corrections as additions/deletions, never local edits to another source.
- Use stable sync metadata for app-authored workout summaries and ignore/reconcile those summaries by local session identity rather than double-counting them as external training.
- Keep all 5/3/1 semantics local and make HealthKit write-back optional to successful manual logging.
- Test authorization combinations, limited history, locked-device retry, replacements/deletions, late routes, force quit/relaunch, and background delivery on a physical iPhone.
