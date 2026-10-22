import Base
import ../src/core/snapshot.bend as SNP
import ../src/core/storedb.bend as SDB
import ../src/core/model.bend as M
import ../src/core/bot.bend as BT
import ../src/core/mail.bend as ML

law snap_thread_rt:
  {SNP.Snap.thread(SNP.Snap.op.json(SDB.Row.thread(SNP.Snap.demo.thread()))) == SNP.Snap.demo.thread() : M.Thread}

def Laws.snap_thread_rt(): {==}

def main() -> IO(Unit):
  IO.print("ok")
