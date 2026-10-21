import Base
import ./mail.bend as ML

# Reading mail is not a disposition. Only a committed reply, an explicit
# deferral/completion, or an escalation of the current input settles it.
# Header order, rather than timestamps, distinguishes same-second mail.
def Continuity.inbound(+m: ML.Mail, +bot: String) -> Bool:
  Bool.and(Bool.not(String.eq(ML.Mail.from(m), "bot:" ++ bot)), Bool.and(String.eq(ML.Mail.wanted(m), "act"),
    Bool.or(String.eq(ML.Mail.to(m), "bot:" ++ bot), String.starts_with(ML.Mail.to(m), "room:"))))

def Continuity.latest.go(ms: List<&2, ML.Mail>, +bot: String, +found: String, done: Bool) -> String:
  match ms done:
    case _ True{}: found
    case Nil{} False{}: found
    case +m <> rest False{}:
      +hit = Continuity.inbound(m, bot)
      Continuity.latest.go(rest, bot, Bool.pick(String, hit, ML.Mail.id(m), found), hit)

def Continuity.latest(ms: List<&2, ML.Mail>, bot: String, fallback: String) -> String:
  Continuity.latest.go(ms, bot, fallback, False{})

def Continuity.reply.of(+m: ML.Mail, +bot: String, +thread: String, +input: String) -> Bool:
  Bool.and(Bool.or(String.eq(ML.Mail.from(m), "bot:" ++ bot), String.eq(ML.Mail.from(m), "thread:" ++ thread)),
    Bool.or(Bool.not(String.eq(ML.Mail.kind(m), "run-reply")), String.eq(ML.Mail.ref(m), input)))

def Continuity.replied.go(ms: List<&2, ML.Mail>, +bot: String, +thread: String, +input: String, answer: Bool, done: Bool) -> Bool:
  match ms done:
    case _ True{}: answer
    case Nil{} False{}: False{}
    case +m <> rest False{}:
      +sent = Continuity.reply.of(m, bot, thread, input)
      +received = Continuity.inbound(m, bot)
      Continuity.replied.go(rest, bot, thread, input, sent, Bool.or(sent, received))

def Continuity.replied(+ms: List<&2, ML.Mail>, +bot: String, +thread: String) -> Bool:
  Continuity.replied.go(ms, bot, thread, Continuity.latest(ms, bot, ""), False{}, False{})

def Continuity.disposed(+status: String) -> Bool:
  Bool.or(String.eq(status, "done"), String.eq(status, "snoozed"))

def Continuity.needs(+token: String, +escalated: String, +forwarded: String, status: String, replied: Bool) -> Bool:
  Bool.and(Bool.not(replied), Bool.and(Bool.not(Continuity.disposed(status)),
    Bool.and(Bool.not(String.eq(token, escalated)), Bool.not(String.eq(token, forwarded)))))
