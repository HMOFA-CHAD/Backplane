# Ordering: intent, Buy it, buy threads

A project says what it is for and what can be made of it. Backplane shows a price for it
and orders it through a buy thread.

## Files in a project

- `.backplane/intent.md`: the person's goal, parts and notes, short.
  - At the start of a request that changes them, the agent has a subagent update it.
  - The person edits it from the project card: Edit puts it in the composer as `/intent ...`, and sending saves it.
- `*.fab.json`, beside each thing to order:
  - fields: `kind` (`pcb`, `3dp`, `cnc` or `sheetmetal`), `name`, `source`, `qty`, `options`, measured `features`;
  - `"order": false` leaves a part out;
  - files under `extra/` and `mfg/` are never read.
- `mfg/<YYYYMMDD-HHMM>/`: what a buy thread exported, with its `manifest.json`.

The agents' instructions are in `src/core/order.bend` (`Order.prompt.project`, `Order.prompt.buy`).

## The card

- **Request:** clients ask `fab.look {thread}` when a thread is chosen and whenever its turn ends (`Fab.sync` in client.bend). A thread opened while its agent works is asked once too, so its card shows at once.
- **The hub's job `fab`** (server/orderio.bend's `Od.look`):
  1. reads the intent and the fab files in the thread's folder;
  2. with the `order.estimates` setting on, asks the order server's `POST /v1/estimate` for the bare parts' price. Only kinds, options and features are sent; never files.
- **The answer** is kept as info keys `fab.line:`, `fab.intent:`, `fab.buy:`, `fab.ready:`, `fab.shown:` and `fab.open:` (plus the thread).
- **Two places:**
  - **The card** at the top of the thread: the goal (click for the whole intent) and Edit.
  - **Ready to order**, right above the message box: the parts by name and Buy it (`Fab.ready`, laws `order_ready_*`, `fab_ready_*`). It shows once the agent's turn is over, never while it works or in a buy thread; on the web it glows once as it comes.

  | Client | Card | Ready to order |
  |---|---|---|
  | Window | `Lay.fab` | `Lay.ready` |
  | Web | `View.fab` (sticky) | `View.ready` |
  | Phones | a queue row, Goal (`Mob.fab`) | a queue row, Ready (`Mob.fab.ready`) |

- **The Buy button's words** (`Card.buy`, laws `order_buy_*`):
  - "Buy it · from $X" with a price;
  - "Buy it" when estimates are off, or when there are boards but no fab files yet;
  - nothing when there is nothing to order or the server is out of reach.

## Buy threads

- **Starting one:** `order.buy {thread}` (hub.bend's `Buy.go`) makes a thread in the same folder, marked `buy.<thread>`, with the person's "Buy it" as its first message.
- **What its agent gets:** the buy instructions and the tools `order_quote` and `order_status`. Only buy threads have them (`Bots.buy.tools`).
- **`order_quote {dir}`** (server.bend's `Od.quote`):
  1. reads the manifest;
  2. refuses unsafe paths and folders holding links;
  3. opens an approval card listing every file ("Send these files for a quote?", Send / Not now);
  4. on Send, uploads them (curl, from the folder, by relative paths), polls the quote, and posts it as a message with the Pay link.
- **The token** lives only in `<home>/orders/<quote>.json` and the Pay link; the agent never sees either.
- **The watcher** (`Od.watch`, resumed at start) asks for the order's state every minute while unpaid and every ten minutes after. It says Paid, Ordered, Shipped (with tracking), Delivered, Refunded or Expired in the thread, once each.

## The server

`order/` (Python): see `order/README.md` for the API, pricing, security and deployment.
- The app's default server is `Order.server()`; the `order.server` setting replaces it.
- The fab's price models are a private pack (`FAB_VENDOR`), not in this repository.
