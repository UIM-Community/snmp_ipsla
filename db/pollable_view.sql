CREATE VIEW IF NOT EXISTS v_pollable_devices
AS 
SELECT DEV1.name, DEV1.ip, DEV1.uuid as dev_uuid, '1' AS snmp_version, V1.uuid, DEV1.dev_id, V1.port, V1.community, '' AS username, '' AS auth_protocol, '' AS auth_key, '' AS priv_protocol, '' AS priv_key FROM nokia_ipsla_snmp_v1 AS V1
JOIN nokia_ipsla_device AS DEV1 ON DEV1.snmp_uuid = V1.uuid WHERE DEV1.is_pollable=1 AND DEV1.is_active=1
UNION
SELECT DEV2.name, DEV2.ip, DEV2.uuid as dev_uuid, '2' AS snmp_version, V2.uuid, DEV2.dev_id, V2.port, V2.community, '' AS username, '' AS auth_protocol, '' AS auth_key, '' AS priv_protocol, '' AS priv_key FROM nokia_ipsla_snmp_v2 AS V2
JOIN nokia_ipsla_device AS DEV2 ON DEV2.snmp_uuid = V2.uuid WHERE DEV2.is_pollable=1 AND DEV2.is_active=1
UNION
SELECT DEV3.name, DEV3.ip, DEV3.uuid as dev_uuid, '3' AS snmp_version, V3.uuid, DEV3.dev_id, V3.port, '' AS community, V3.username, V3.auth_protocol, V3.auth_key, V3.priv_protocol, V3.priv_key FROM nokia_ipsla_snmp_v3 AS V3
JOIN nokia_ipsla_device AS DEV3 ON DEV3.snmp_uuid = V3.uuid WHERE DEV3.is_pollable=1 AND DEV3.is_active=1