// The JS twin of cast.c: the JS host shows no browser pages, so no client
// is ever casting.
function cast_seen(client, page) {
  return { $: "False" };
}

function cast_to(page) {
  return { $: "Nil" };
}

io_eff(CID(Cast.seen), cast_seen);
io_eff(CID(Cast.to), cast_to);
