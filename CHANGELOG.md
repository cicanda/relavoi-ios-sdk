## 0.2.0

### Phone numbers: the server decides, not the SDK

The client-side check was strict E.164 (`^\+[1-9]\d{6,14}$`). It was wrong in
both directions, and the second direction is the one that hurt:

* It **refused numbers the API accepts.** Someone typing `08031234567`, or
  pasting `0803 123 4567` out of their contacts, got a client-side error for a
  number the platform would have taken. Only the full `+234...` form worked.
* It **accepted numbers the API refuses**, such as a UK mobile or a Nigerian
  landline, so the SDK let a call to `create` through and the server refused it.

The check is now deliberately light: non-empty, digits, with an optional leading
plus. Separators (spaces, brackets, hyphens, dots, non-breaking spaces, Unicode
dashes) are stripped using the same set the server strips, so the SDK cannot
reject a value the API would accept. The server owns the rule, reads it from its
countries table, and can change it without a new SDK release.

### Two new typed errors

The server's refusals now arrive as cases you can switch on, rather than a
generic `.validation`:

* `.numberNotSupported(detail:)` for a number Relavoi does not connect. Today
  that means anything other than a Nigerian mobile.
* `.crossBorderNotSupported(detail:)` when the two parties are not in the same
  country.

Both are matched on the problem document's `type` slug, so they work against any
environment. Neither detail contains the number that was refused.

### No part of a phone number in any message or log line

Several places leaked digits, and one leaked whole numbers:

* The validation error appended the **last four digits** of the rejected value.
  Removed. The detail now names the field and the expected shape, nothing else.
* Request logging wrote the **full path including the query string**, and
  `/sessions/verify` carries the subscriber's number there. With SDK logging on,
  that put a plaintext phone number in the unified log. Only the path is logged
  now, and the same applies to the `.unexpected` message for a non-HTTP response.
* `PhoneUtils.mask` returned `+****5678`, and those last four digits were logged
  for both parties on session creation. The function is gone and that line no
  longer carries a number.
* Error responses no longer surface a **raw body**. Only `type` and `detail` are
  read from a problem document. An error page from in front of the API commonly
  echoes the request URI, which is how a number would have reached a crash
  reporter.

### Possibly breaking

* `RelavoiError` has two new cases. An exhaustive `switch` over it will need
  them.
* `.api(statusCode:body:)` no longer carries the raw response body. `body` is
  now the problem `detail`, or nil. The status code is unchanged.
* `.unauthorized(detail:)` carries the problem `detail` rather than the raw body.
* `PhoneUtils` is internal, but if you reached it: `requireValidE164` is now
  `requireNumberShaped` and returns the canonical form, `validateE164` is now
  `looksLikeNumber`, and `mask` is removed.
* Numbers are sent with separators stripped. `0803 123 4567` goes out as
  `08031234567`.

## 0.1.0

* First release: auth, sessions, call verification, push registration,
  WebSocket events, presence, Live Activities and the offline queue.
