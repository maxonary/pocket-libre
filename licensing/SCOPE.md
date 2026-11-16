# License boundaries and provenance

Status: proposed separation, not an adopted license change (2026-11-16).
The existing root `LICENSE` remains unchanged. Do not distribute the new extension
snapshot as restricted software until the draft has been adopted with an exact
scope and consistent release notices. Publishing it under the present blanket
MIT notice could grant rights the proposed restriction is intended to reserve.

## MIT foundation and previously published app

- Upstream baseline: `5962722`, Pocket Libre by Shah Baig and contributors.
- Published fork baseline: `15e10de60d63d2462dcbbf07b577ae6e008167f5`.
  `git ls-remote origin refs/heads/main` returned this commit on 2026-11-16.
- The upstream baseline has no `ios/` tree. Commit `15e10de` adds the first native
  app and Python changes while the root license and README identify MIT.
- Treat the entire published baseline's applicable MIT software rights as
  preserved, including the first iPhone app. Its implementation is not newly
  exclusive merely because it was developed for this fork.
- The Python package remains MIT; its `pyproject.toml` metadata is unchanged.
- Existing device protocol/Bluetooth/Wi-Fi code stays in the MIT foundation.
  New interfaces calling that code do not alter its license.

## Candidate new extension material

`scope-manifest.json` records exact source hashes, baseline blob hashes and
classification for the current local app source, tests and build configuration.
It is evidence of a local comparison, not proof of copyright ownership or of the
absence of other releases. The candidate-new files are journal archive, sync,
notes UI and local retrieval/chat, their tests, and the native container plist.

Mixed files (player, library, app UI, device rendering, tests and build setup)
retain all MIT baseline rights. Only original, post-baseline additions are
candidates for the proposed terms. Identify those additions using the exact
baseline/current pair in the manifest; never label a mixed file exclusively
noncommercial. Any reused third-party expression remains excluded even if it
appears in a new file or a new diff hunk. A diff alone is not an ownership audit.

This is a licensing boundary, not a runtime reorganization: source files stay at
their working paths so Xcode references and imports do not change. There is no
claim that the extension layer is independently buildable or contains no reused
expression. Future extraction into a separate module can simplify the boundary.

## Exclusions

- `LICENSE` and all existing upstream copyright/permission notices.
- `ios/PocketLibre/ThirdPartyNotices.txt`, dependency code, model weights,
  tokenizers and Apple frameworks: their own terms apply.
- Existing app icons, product images, fonts, logos and other brand assets are not
  claimed as newly owned software. Their rights need a separate asset audit.
- Generated project artifacts and factual configuration values are not assumed
  copyrightable merely because they changed.
- User recordings, transcripts, notes, session keys and backups are not covered.
- Earlier releases and any grants already made remain unaffected. The Git audit
  does not establish what grants accompanied TestFlight binaries or other copies;
  inspect those artifacts before adopting the boundary for a release.

## Adoption steps

1. Confirm whether Maximilian Arnold personally or an entity owns each new
   contribution; obtain any needed contributor permissions. Confirm asset rights
   separately. The name in the draft is a proposal, not an ownership finding.
2. Review `drafts/APP-NONCOMMERCIAL.md`, especially its definition of commercial
   use (including internal business use) and any founder/team authorizations.
   The draft deliberately has no blanket nonprofit/government exception.
3. Review exact new files and mixed-file additions against the baseline and
   third-party sources. Regenerate and freeze the manifest for the actual release.
4. Adopt a versioned license with that manifest; add precise notices to covered
   files and mixed additions, update the root licensing overview and bundle the
   adopted terms alongside preserved third-party notices. Keep the Python MIT
   package metadata. Do not replace the upstream MIT license with the new terms.
5. Issue separate written commercial grants when needed, specifying the recipient,
   version, uses, duration, price (including zero if agreed) and redistribution.

No repository visibility change, publication, contributor agreement, commercial
grant or change to previously granted rights is performed by this preparation.
