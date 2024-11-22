local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
# example:
#  ec2: 
function(cluster='cluster1')
{
  local config = {
    name: "pingcap-setup-sysbench-single",
    client_1_tags: [cluster + '-sysbench-1'],
    tidb_1_tags: [cluster + '-tidb-1'],
  },  
  local sysbench_config = [
    "mysql-host=TIDB_1_IP",
    "mysql-port=4000",
    "mysql-user=root",
    "mysql-password=TIDB_PASSWORD",
    "mysql-db=sbtest",
    "db-driver=mysql"
  ],
  metadata: config,
  name: config.name,
  jobs: {
    client_1: {
      host: {
        tags: config.client_1_tags,
      },       
      steps: [
        systemslab.write_file('./config', std.lines(sysbench_config)),
        bash(
          |||          
            TIDB_PASSWORD=`cat ~/tidb_password.txt`
            sed -ie "s/TIDB_1_IP/${TIDB_1_ADDR}/g" ./config
            sed -ie "s/TIDB_PASSWORD/${TIDB_PASSWORD}/g" ./config
            cat ./config
            cp ./config ~/config       
            echo 'set global tidb_disable_txn_auto_retry = off;' > ./disable.sql
            echo 'create database sbtest;' > ./create_sbtest.sql            
            bash -c "mysql --host=${TIDB_1_ADDR} -P 4000 -p${TIDB_PASSWORD} --user=root < ./disable.sql" || true
            bash -c "mysql --host=${TIDB_1_ADDR} -P 4000 -p${TIDB_PASSWORD} --user=root < ./create_sbtest.sql" || true
            time sysbench --config-file=config oltp_point_select --tables=10 --table-size=10000000 prepare
          |||
        ),
      ],
    },
    tidb_1: {
      host: {
        tags: config.tidb_1_tags,         
      },
      steps : []
    },
  }
}