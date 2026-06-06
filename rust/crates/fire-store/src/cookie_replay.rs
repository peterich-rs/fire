use rusqlite::{params, Connection};

pub struct CookieReplayEntry {
    pub url: String,
    pub raw_set_cookie: String,
    pub cookie_name: String,
    pub domain: String,
    pub inserted_at: u64,
}

pub fn enqueue_set_cookie(
    conn: &Connection,
    url: &str,
    raw_set_cookie: &str,
    cookie_name: &str,
    domain: &str,
    inserted_at: u64,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT OR REPLACE INTO cookie_replay_queue (url, raw_set_cookie, cookie_name, domain, inserted_at)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![url, raw_set_cookie, cookie_name, domain, inserted_at as i64],
    )?;
    Ok(())
}

pub fn list_replay_queue(conn: &Connection) -> rusqlite::Result<Vec<CookieReplayEntry>> {
    let mut stmt = conn.prepare(
        "SELECT url, raw_set_cookie, cookie_name, domain, inserted_at FROM cookie_replay_queue ORDER BY inserted_at ASC"
    )?;
    let entries = stmt
        .query_map([], |row| {
            Ok(CookieReplayEntry {
                url: row.get(0)?,
                raw_set_cookie: row.get(1)?,
                cookie_name: row.get(2)?,
                domain: row.get(3)?,
                inserted_at: row.get::<_, i64>(4)? as u64,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(entries)
}

pub fn clear_replay_queue(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM cookie_replay_queue", [])?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replay_queue_listing_preserves_entries_until_explicit_clear() {
        let conn = Connection::open_in_memory().expect("open in-memory sqlite");
        conn.execute_batch(
            "CREATE TABLE cookie_replay_queue (
                url TEXT NOT NULL,
                raw_set_cookie TEXT NOT NULL,
                cookie_name TEXT NOT NULL,
                domain TEXT NOT NULL,
                inserted_at INTEGER NOT NULL
            );
            CREATE UNIQUE INDEX idx_cookie_replay_dedup
                ON cookie_replay_queue (cookie_name, domain);",
        )
        .expect("create schema");

        enqueue_set_cookie(
            &conn,
            "https://linux.do/",
            "_t=token; Path=/; SameSite=Lax; HttpOnly",
            "_t",
            "linux.do",
            42,
        )
        .expect("enqueue");

        let first = list_replay_queue(&conn).expect("first list");
        let second = list_replay_queue(&conn).expect("second list");

        assert_eq!(first.len(), 1);
        assert_eq!(second.len(), 1);
        assert_eq!(first[0].raw_set_cookie, second[0].raw_set_cookie);

        clear_replay_queue(&conn).expect("clear");
        assert!(list_replay_queue(&conn).expect("empty list").is_empty());
    }
}
