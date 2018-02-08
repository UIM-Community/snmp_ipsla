CREATE TABLE IF NOT EXISTS "nokia_ipsla_device" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"uuid" CHAR(36) NOT NULL,
"snmp_uuid" CHAR(36) NOT NULL,
"name" VARCHAR(60) NOT NULL,
"ip" VARCHAR(45) NOT NULL,
"is_pollable" BOOLEAN DEFAULT 1
);

CREATE TABLE IF NOT EXISTS "nokia_ipsla_device_attr" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"dev_uuid" CHAR(36) NOT NULL,
"key" TEXT(255) NOT NULL,
"value" TEXT(255) DEFAULT NULL
);

CREATE TABLE IF NOT EXISTS "nokia_ipsla_snmp_v1" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"uuid" CHAR(36) NOT NULL,
"description" TEXT(255),
"community" TEXT(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS "nokia_ipsla_snmp_v2" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"uuid" CHAR(36) NOT NULL,
"description" TEXT(255),
"community" TEXT(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS "nokia_ipsla_snmp_v3" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"uuid" CHAR(36) NOT NULL,
"description" TEXT(255),
"username" VARCHAR(60) NOT NULL,
"auth_protocol" VARCHAR(15),
"auth_key" TEXT(255),
"priv_protocol" VARCHAR(15),
"priv_key" TEXT(255)
);

CREATE VIEW v_pollable_devices
AS 
SELECT DEV1.name, DEV1.ip, '1' AS snmp_version, V1.uuid, V1.community, '' AS username, '' AS auth_protocol, '' AS auth_key, '' AS priv_protocol, '' AS priv_key FROM nokia_ipsla_snmp_v1 AS V1
JOIN nokia_ipsla_device AS DEV1 ON DEV1.snmp_uuid = V1.uuid WHERE DEV1.is_pollable=1
union
SELECT DEV2.name, DEV2.ip, '2' AS snmp_version, V2.uuid, V2.community, '' AS username, '' AS auth_protocol, '' AS auth_key, '' AS priv_protocol, '' AS priv_key FROM nokia_ipsla_snmp_v2 AS V2
JOIN nokia_ipsla_device AS DEV2 ON DEV2.snmp_uuid = V2.uuid WHERE DEV2.is_pollable=1
union
SELECT DEV3.name, DEV3.ip, '3' AS snmp_version, V3.uuid, '' AS community, V3.username, V3.auth_protocol, V3.auth_key, V3.priv_protocol, V3.priv_key FROM nokia_ipsla_snmp_v3 AS V3
JOIN nokia_ipsla_device AS DEV3 ON DEV3.snmp_uuid = V3.uuid WHERE DEV3.is_pollable=1;