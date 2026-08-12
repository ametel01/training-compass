# Decide local data ownership and lifecycle

Type: grilling
Status: resolved
Blocked by: 01, 06

## Question

What data must the app own locally versus re-derive from HealthKit, and what lifecycle guarantees are required for privacy, offline use, backup, export, reset, deletion, and recovery? Resolve the intended behavior without prematurely choosing a storage framework.

## Answer

### Ownership and offline behavior

- Training Compass separates persisted information into three classes. **Locally Authoritative Data** contains all user-created or user-confirmed facts for which the app is the source of truth: Schedule Templates and Training Cycles; 5/3/1 Sessions, prescriptions, results, and notes; lift configuration and Training Max history; preferences; explicit Training Event links; corrections; and audit history.
- The **HealthKit Mirror** contains imported Apple Health objects, their HealthKit UUIDs, available provenance, deletion and reconciliation state, and the sync state required to maintain the mirror. Apple Health remains authoritative for those objects.
- **Derived Projections** include e1RM trends, rolling insights, Personal Recovery Baselines, Recovery Guidance, and other reproducible views. They are never authoritative records and may be discarded and rebuilt from their source facts.
- Locally Authoritative Data and the existing HealthKit Mirror remain usable offline. Health-dependent views expose their last reconciliation state rather than implying freshness; local 5/3/1 planning and logging never depend on current Health access.
- The mirror has no automatic age limit. Reduced or revoked Health authorization stops or limits future reconciliation but does not silently purge imported history. Because HealthKit does not reveal a hidden read-permission state reliably, absence of new readable data is never treated as proof of denial.

### Backup and restoration

- Locally Authoritative Data participates in the owner's encrypted Apple device or iCloud Backup. This is ordinary device recovery, not an account system, app-operated cloud storage, CloudKit synchronization, or a cross-device merge capability.
- The HealthKit Mirror, Derived Projections, and sync cursors are excluded from device backup. After device restoration, Training Compass restores its locally authoritative facts, requests or confirms Health access again, rebuilds the mirror from the data then available in HealthKit, reconnects exact UUID matches, and then regenerates projections.
- Until reconciliation and regeneration finish, Health-dependent views are visibly incomplete or stale. A missing HealthKit object does not invalidate a restored local Session or erase its historical link facts.
- Without a usable Apple device backup or a Training Compass Export, deleting the app permanently loses its locally authoritative details. HealthKit Write-backs are summaries and never serve as a backup of sets, loads, Training Maxes, e1RM evidence, or audit history.

### Export and import

- A **Training Compass Export** is one versioned, self-contained archive. It always includes every Locally Authoritative Data record as a human-readable summary and as full-fidelity machine-readable data with stable identities.
- The user may explicitly include a separate, clearly source-labelled snapshot of the HealthKit Mirror. That snapshot records the provenance and reconciliation context available at export time, but Apple Health remains authoritative. Derived Projections are not canonical export data because they can be regenerated.
- The initial export format is portable and unencrypted. Before creation, the app warns that the archive contains sensitive fitness data. It creates an export only on demand, hands it to the system share flow, and removes its temporary copy afterward; the user-selected destination is responsible for its retained copy.
- Import is a recovery capability, not just a reader. It restores Locally Authoritative Data with stable identities. An included HealthKit snapshot remains reference material and is never installed as the live mirror; the app rebuilds that mirror from current HealthKit data and reconnects exact UUIDs.
- Import into a non-empty app replaces the current dataset rather than merging records. Replacement requires explicit confirmation and strongly prompts the user to export the current data first.
- Before altering current data, import validates the archive manifest, integrity, relationships, and schema and applies explicit migrations for every earlier released Training Compass export version. Corrupt or incomplete archives and unsupported future versions are rejected with an explanation. Replacement is transactional: any failure leaves the current dataset unchanged, and projections rebuild only after a successful commit.

### Reset, deletion, and recovery controls

- **Health Data Rebuild** discards the HealthKit Mirror, Derived Projections, and sync cursors, then reconciles again from currently available HealthKit data. It preserves all Locally Authoritative Data, including explicit Training Event links and their audit history. Exact HealthKit UUIDs reconnect when they return.
- **Full App Erasure** removes all Locally Authoritative Data, the mirror, projections, preferences, and sync state from the current installation and returns the app to first launch. It is the deliberate route for purging Completed and Abandoned Training Cycles, which remain non-deletable individually under the cycle lifecycle rules.
- Before Full App Erasure, the user may separately choose to delete Training Compass HealthKit Write-backs. The app never deletes another source's workouts. If deleting app-authored summaries fails, the user chooses between retrying and proceeding with local erasure after acknowledging that some summaries will remain.
- Without that separate choice, Full App Erasure and ordinary app uninstall leave HealthKit data untouched. Later reinstallation or import may reconnect an exact surviving write-back through its stable sync identity.

### Privacy and erasure boundary

- The initial product relies on normal iPhone device protection and does not add a separate Face ID or passcode gate. Sensitive content is excluded from app-switcher snapshots, while export and destructive operations require explicit confirmation.
- Full App Erasure promises removal from the current installation, not forensic deletion from storage outside it. Prior device or iCloud backups, previously shared exports, and retained HealthKit workouts are separate copies that the owner must manage through their respective Apple or destination controls.
