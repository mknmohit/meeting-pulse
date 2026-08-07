# axdump

`axdump` is a development-only Accessibility inspection tool. It is not
bundled into Meeting Pulse and must never be used to upload or publish a dump.

Build it with:

```sh
cd mac-app/Tools/axdump
swift build -c release
```

Capture a tree:

```sh
.build/release/axdump --bundle com.google.Chrome --depth 20 --out dumps/meet-active-fg.json
```

Watch Accessibility notifications:

```sh
.build/release/axdump --watch --bundle com.google.Chrome
```

Compare two captures:

```sh
.build/release/axdump --diff dumps/before.json dumps/after.json
```

Captures can contain private window text. Keep them local until they have been
sanitised under the rules in the implementation plan.
