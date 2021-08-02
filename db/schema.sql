-- 5000 records
-- SELECT id, nickname FROM users WHERE id = ?
-- SELECT * FROM users WHERE login_name = ?'
-- INSERT INTO users (login_name, pass_hash, nickname) VALUES (?, SHA2(?, 256), ?)
-- SELECT id, nickname FROM users WHERE id = ?
CREATE TABLE IF NOT EXISTS users (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nickname    VARCHAR(128) NOT NULL,
    login_name  VARCHAR(128) NOT NULL,
    pass_hash   VARCHAR(128) NOT NULL,
    UNIQUE KEY login_name_uniq (login_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 18 records
-- SELECT * FROM events ORDER BY id ASC
-- SELECT * FROM events WHERE id = ?
-- INSERT INTO events (title, public_fg, closed_fg, price) VALUES (?, ?, 0, ?)
-- UPDATE events SET public_fg = ?, closed_fg = ? WHERE id = ?
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    title       VARCHAR(128)     NOT NULL,
    public_fg   TINYINT(1)       NOT NULL,
    closed_fg   TINYINT(1)       NOT NULL,
    price       INTEGER UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1000 records
-- SELECT COUNT(*) AS total_sheets FROM sheets WHERE `rank` = ?'
--- SELECT * FROM sheets WHERE id NOT IN (SELECT sheet_id FROM reservations WHERE event_id = ? AND canceled_at IS NULL FOR UPDATE) AND `rank` = ? ORDER BY RAND() LIMIT 1
-- SELECT * FROM sheets WHERE `rank` = ? AND num = ?
-- 'SELECT * FROM sheets ORDER BY `rank`, num'
CREATE TABLE IF NOT EXISTS sheets (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    `rank`      VARCHAR(128)     NOT NULL,
    num         INTEGER UNSIGNED NOT NULL,
    price       INTEGER UNSIGNED NOT NULL,
    UNIQUE KEY rank_num_uniq (`rank`, num)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 194516 records
-- SELECT * FROM reservations WHERE event_id = ? AND sheet_id = ? AND canceled_at IS NULL GROUP BY event_id, sheet_id HAVING reserved_at = MIN(reserved_at)
-- SELECT r.*, s.rank AS sheet_rank, s.num AS sheet_num FROM reservations r INNER JOIN sheets s ON s.id = r.sheet_id WHERE r.user_id = ? ORDER BY IFNULL(r.canceled_at, r.reserved_at) DESC LIMIT 5
-- SELECT IFNULL(SUM(e.price + s.price), 0) AS total_price FROM reservations r INNER JOIN sheets s ON s.id = r.sheet_id INNER JOIN events e ON e.id = r.event_id WHERE r.user_id = ? AND r.canceled_at IS NULL
-- SELECT event_id FROM reservations WHERE user_id = ? GROUP BY event_id ORDER BY MAX(IFNULL(canceled_at, reserved_at)) DESC LIMIT 5
-- SELECT * FROM sheets WHERE id NOT IN (SELECT sheet_id FROM reservations WHERE event_id = ? AND canceled_at IS NULL FOR UPDATE) AND `rank` = ? ORDER BY RAND() LIMIT 1
-- SELECT * FROM reservations WHERE event_id = ? AND sheet_id = ? AND canceled_at IS NULL GROUP BY event_id HAVING reserved_at = MIN(reserved_at) FOR UPDATE
-- UPDATE reservations SET canceled_at = ? WHERE id = ?
-- SELECT r.*, s.rank AS sheet_rank, s.num AS sheet_num, s.price AS sheet_price, e.price AS event_price FROM reservations r INNER JOIN sheets s ON s.id = r.sheet_id INNER JOIN events e ON e.id = r.event_id WHERE r.event_id = ? ORDER BY reserved_at ASC FOR UPDATE
CREATE TABLE IF NOT EXISTS reservations (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    event_id    INTEGER UNSIGNED NOT NULL,
    sheet_id    INTEGER UNSIGNED NOT NULL,
    user_id     INTEGER UNSIGNED NOT NULL,
    reserved_at DATETIME(6)      NOT NULL,
    canceled_at DATETIME(6)      DEFAULT NULL,
    last_updated_at DATETIME(6) AS (IFNULL(canceled_at, reserved_at)) PERSISTENT,
    not_canceled BOOLEAN AS (ISNULL(canceled_at)) PERSISTENT,
    KEY event_id_and_sheet_id_idx (event_id, sheet_id, not_canceled),
    KEY user_id_and_last_updated_at (user_id, last_updated_at),
    KEY user_id_and_event_id (user_id, event_id, last_updated_at),
    KEY user_id_and_not_canceled(user_id, not_canceled),
    KEY reserved_at(reserved_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- 105 records
-- SELECT id, nickname FROM administrators WHERE id = ?
-- SELECT * FROM administrators WHERE login_name = ?
CREATE TABLE IF NOT EXISTS administrators (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nickname    VARCHAR(128) NOT NULL,
    login_name  VARCHAR(128) NOT NULL,
    pass_hash   VARCHAR(128) NOT NULL,
    UNIQUE KEY login_name_uniq (login_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
