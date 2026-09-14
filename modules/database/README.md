# Database module

Tạo một DB subnet group từ đúng hai private database subnet, các log groups cho engine log exports (nếu bật), và đúng một RDS instance. Log groups được tạo trước RDS để AWS có thể ghi log với retention đã chọn. RDS luôn `publicly_accessible = false`, `multi_az = false`, mã hóa storage và chỉ cho phép cổng database từ EC2 security group. Không có replica, cluster hay instance thứ hai.

Engine, version, class, storage, backup, deletion protection và lifecycle được nhận từ input environment. Password là sensitive input nhưng vẫn có thể xuất hiện trong Terraform state; cấp qua `TF_VAR_db_password`, secret backend hoặc cơ chế CI phù hợp, không commit vào Git.

| Input chính | Output chính |
|---|---|
| engine/version/class/storage | `db_instance_arn`, `db_instance_identifier` |
| private subnets, SG, credentials | `db_address`, `db_endpoint`, `db_port` |
| backup/deletion lifecycle | `db_subnet_group_name` |
