INSERT INTO cm_configuration_item_definition (ci_type,ci_parent,ci_description) VALUES ('9.1.2','9.1','Private.Device.Nokia');
INSERT INTO cm_configuration_item_definition (ci_type,ci_parent,ci_description) VALUES ('9.1.2.1','9.1.2','Private.Device.Nokia.ResponsePathTest');

INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2:0','Reachability','','9.1.2');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2:1','GetTableFail','','9.1.2');

INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:0','TestRunResult','','9.1.2.1');

INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:1','MinRttWithPrecision','µs','9.1.2.1');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:3','AvgRttWithPrecision','µs','9.1.2.1');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:2','MaxRttWithPrecision','µs','9.1.2.1');

INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:4','MinTtWithPrecision','µs','9.1.2.1');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:10','AverageTtWithPrecision','µs','9.1.2.1');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:5','MaxTtWithPrecision','µs','9.1.2.1');

INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:6','MinInTtWithPrecision','µs','9.1.2.1');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:11','AverageInTtWithPrecision','µs','9.1.2.1');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:7','MaxInTtWithPrecision','µs','9.1.2.1');

INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:8','OutJitterWithPrecision','µs','9.1.2.1');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:9','InJitterWithPrecision','µs','9.1.2.1');
INSERT INTO cm_configuration_item_metric_definition (met_type, met_description, unit_type, ci_type) VALUES ('9.1.2.1:12','RtJitterWithPrecision','µs','9.1.2.1');