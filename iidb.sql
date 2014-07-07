PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE 'messages' ('id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, 'echo' VARCHAR(45), 'fr
om_user' TEXT, 'to_user' TEXT, 'subg' VARCHAR(50), 'time' TIMESTAMP, 'hash' VARCHAR(30), 'read' I
NT, 'post' TEXT);
CREATE TABLE 'output' ('id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, 'echo' VARCHAR(45), 'from
_user' TEXT, 'to_user' TEXT, 'subg' VARCHAR(50), 'time' TIMESTAMP, 'hash' VARCHAR(30), 'send' INT
, 'post' TEXT, base64 TEXT);
CREATE TABLE echo('echo' VARCHAR(32), 'hash' VARCHAR(32));
COMMIT;
