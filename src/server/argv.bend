import Base

# The program's own arguments. Bend 2.0.36's IO.args() starts with the
# program's name (argv[0]); every flag and file a program reads comes after
# it (the mains do the same through server/review.bend's Rvc.main).

def Argv.rest(xs: List<String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case _ <> t:
      t

def Argv.args() -> IO(List<String>):
  IO.bind(List<String>, List<String>, IO.args(), xs => IO.pure(List<String>, Argv.rest(xs)))
