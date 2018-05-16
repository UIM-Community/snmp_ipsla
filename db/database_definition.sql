CREATE TABLE IF NOT EXISTS "nokia_ipsla_device" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"uuid" CHAR(36) NOT NULL,
"snmp_uuid" CHAR(36) NOT NULL,
"name" VARCHAR(100) NOT NULL,
"ip" VARCHAR(45) NOT NULL,
"dev_id" CHAR(33) NOT NULL,
"is_active" BOOLEAN DEFAULT 1,
"is_pollable" BOOLEAN DEFAULT 1
);

CREATE TABLE IF NOT EXISTS "nokia_ipsla_metrics" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"name" VARCHAR(100) NOT NULL,
"device_name" VARCHAR(100) NOT NULL,
"source" VARCHAR(45) NOT NULL,
"probe" VARCHAR(100) NOT NULL,
"type" VARCHAR(25) NOT NULL,
"value" INTEGER NOT NULL,
"time" DATETIME NOT NULL
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
"port" CHAR(5) NOT NULL,
"community" TEXT(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS "nokia_ipsla_snmp_v2" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"uuid" CHAR(36) NOT NULL,
"description" TEXT(255),
"port" CHAR(5) NOT NULL,
"community" TEXT(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS "nokia_ipsla_snmp_v3" (
"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
"uuid" CHAR(36) NOT NULL,
"port" CHAR(5) NOT NULL,
"description" TEXT(255),
"username" VARCHAR(60) NOT NULL,
"auth_protocol" VARCHAR(15),
"auth_key" TEXT(255),
"priv_protocol" VARCHAR(15),
"priv_key" TEXT(255)
);