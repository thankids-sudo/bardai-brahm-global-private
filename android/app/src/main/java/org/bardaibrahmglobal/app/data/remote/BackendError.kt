package org.bardaibrahmglobal.app.data.remote

/** Every backend failure the app distinguishes. Server messages are not shown to users. */
sealed class BackendError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class NotConfigured : BackendError("backend not configured")
    class Network(cause: Throwable) : BackendError("network unavailable", cause)
    class NotSignedIn : BackendError("not signed in")
    /** Access token rejected; the session layer refreshes once and retries. */
    class Unauthorized : BackendError("token rejected")
    class InvalidCredentials : BackendError("invalid email or password")
    class EmailNotConfirmed : BackendError("email not confirmed")
    class WeakPassword : BackendError("password too weak")
    class RateLimited : BackendError("too many requests")
    /** 42501: the database refused the action for this user. */
    class NotAllowed : BackendError("not allowed")
    /** P0002 */
    class NotFound : BackendError("not found")
    /** 22023 / 23514 / 22xxx: input rejected by a rule. */
    class InvalidInput : BackendError("invalid input")
    /** 23505 */
    class AlreadyExists : BackendError("already exists")
    /** 55000: e.g. application no longer pending. */
    class WrongState : BackendError("wrong state")
    /** 54000: rate limits inside the database (directory, contacts). */
    class LimitReached : BackendError("limit reached")
    class Server(val code: String?) : BackendError("server error ${code.orEmpty()}")

    companion object {
        /** Maps a PostgreSQL SQLSTATE (as returned by PostgREST in `code`) to an error. */
        fun fromSqlState(code: String?): BackendError = when {
            code == null -> Server(null)
            code == "42501" -> NotAllowed()
            code == "28000" -> Unauthorized()
            code == "P0002" -> NotFound()
            code == "23505" -> AlreadyExists()
            code == "55000" -> WrongState()
            code == "54000" -> LimitReached()
            code == "23514" || code.startsWith("22") -> InvalidInput()
            code.startsWith("PGRST30") -> Unauthorized()   // JWT expired / invalid
            else -> Server(code)
        }
    }
}
