import Base
import ./check.bend as C
import ./thin_mail_adoption_test.bend as T
import ./thin_mail_actor_fixture.bend as F
import ../src/server/thin-actor.bend as TA

def main() -> IO(Unit):
  do IO<Unit>:
    +old : TA.Actor = T.adopted(T.state())
    +reply : TA.Actor = T.list_reply(TA.Actor.mail_ready(old))
    C.Check.str("old adopted aggregate retains real canonical RPC room rows", T.listed(reply), "act-c,room:ra,room:rb,")
