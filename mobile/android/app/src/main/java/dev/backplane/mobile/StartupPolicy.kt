package dev.backplane.mobile

// Explicit compatibility applies only to this running app session.
enum class StartupPolicy { DISCOVERING, THIN, COMPATIBILITY_REQUIRED, COMPATIBILITY_CHOSEN }

// Owner identity alone cannot distinguish two tabs of the same bot.
class ThinPresentationFence {
    private var epoch: Long? = null
    private var revision = 0L
    private var active = false

    fun observe(update: SyncUpdate, epoch: Long) = update.thinPresenting && begin(epoch, update.requestRevision)

    fun begin(epoch: Long, revision: Long): Boolean {
        if (revision !in 1..4294967295L || (this.epoch == epoch && revision <= this.revision)) return false
        this.epoch = epoch
        this.revision = revision
        active = true
        return true
    }

    fun accepts(epoch: Long, revision: Long) = active && this.epoch == epoch && this.revision == revision

    fun invalidate() { active = false }
}
