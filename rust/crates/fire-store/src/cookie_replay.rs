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

pub fn drain_replay_queue(conn: &Connection) -> rusqlite::Result<Vec<CookieReplayEntry>> {
    let mut stmt = conn.prepare(
        "SELECT url, raw_set_cookie, cookie_name, domain, inserted_at FROM cookie_replay_queue ORDER BY inserted_at ASC"
    )?;
    let entries = stmt.query_map([], |row| {
        Ok(CookieReplayEntry {
            url: row.get(0)?,
            raw_set_cookie: row.get(1)?,
            cookie_name: row.get(2)?,
            domain: row.get(3)?,
            inserted_at: row.get::<_, i64>(4)? as u64,
        })
    })?.collect::<Result<Vec<_>, _>>()?;
    Ok(entries)
}

pub fn clear_replay_queue(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM cookie_replay_queue", [])?;
    Ok(())
}
