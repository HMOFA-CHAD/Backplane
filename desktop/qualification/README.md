# Browser regression qualification

These integration checks exercise the browser callbacks against retained emitted Bend exports. They run separately from `npm test` because they require an external compiler fixture.

Set `BP_ROUTE_BEND_BUNDLE` to the retained `thin-coherent-emitted-v1/host-wire/chunk-x4j34c3m.js` fixture with SHA-256 `9c7fb73cee7f7f42ff48e65e1eb7c08d33aa2c2cb41314e0cde55d5b0a71598a`, then run:

```sh
node --test desktop/qualification/chat-route-regression.test.cjs desktop/qualification/thin-continuations.test.cjs
```

The checks stop before the fixture's original test suite and verify its bytes before evaluating the emitted exports. They cover route retention, captured Send preparation without dispatch, late-response fencing, exact continuation ownership, memo expansion, bounded cursors and inline plaintext. They fail explicitly when the fixture is absent or differs. The retained exports establish focused callback behavior; they do not certify a new production bundle or native platform runtime.
