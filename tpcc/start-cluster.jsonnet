local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function(clustername="systemslab-test", storage="/mnt/localssd-1", warehouses=10, partitions=1)
{
  local topology = {
    global: {
      user: "systemslab-agent",
      ssh_port: 22,
      deploy_dir: storage + "/tidb-deploy",
      data_dir: storage + "/tidb-data",
      listen_host: "0.0.0.0",
      arch: "amd64",
    },
    pd_servers: [{ host: "PD_SERVER_IP"}],
    tidb_servers: [{ host: "TIDB_SERVER_IP"}],
    tikv_servers: [{ host: "TIKV_SERVER_IP"}],       
  },
  name: "start-pingcap-cluster",
  jobs: {
    tiup_control: {
      host: {
        tags: ['pingcap', 'i3en-2xlarge-1'],    
      },       
      steps: [
        # cleaning up the data also any remaining tidb processes
        bash(        
          |||
            ~/.tiup/bin/tiup cluster destroy systemslab-test -y || true
          |||
        ),
        systemslab.barrier('cluster-up'),
        systemslab.write_file('topology.yaml', std.manifestYamlDoc(topology, indent_array_in_object=true, quote_keys=false)),
        bash(
          |||
            sed -ie "s/PD_SERVER_IP/${PD_SERVER_ADDR}/g" topology.yaml
            echo "PD SERVER at ${PD_SERVER_ADDR}"
            sed -ie "s/TIDB_SERVER_IP/${TIDB_SERVER_ADDR}/g" topology.yaml
            echo "TIDB SERVER at ${TIDB_SERVER_ADDR}"
            sed -ie "s/TIKV_SERVER_IP/${TIKV_SERVER_ADDR}/g" topology.yaml
            echo "TIKV SERVER at ${TIKV_SERVER_ADDR}"
            sed -ie "s/TIFLASH_SERVER_IP/${TIFLASH_SERVER_ADDR}/g" topology.yaml
            echo "TIFLASH SERVER at ${TIFLASH_SERVER_ADDR}"
          |||
        ),
        systemslab.upload_artifact('topology.yaml'),
        bash('~/.tiup/bin/tiup cluster check ./topology.yaml --user systemslab-agent | tee tiup_check_log'),
        systemslab.upload_artifact('tiup_check_log'),
        bash('~/.tiup/bin/tiup cluster deploy systemslab-test v8.0.0 ./topology.yaml --user systemslab-agent -y --ignore-config-check | tee tiup_deploy_log'),
        systemslab.upload_artifact('tiup_deploy_log'),
        bash('~/.tiup/bin/tiup cluster start systemslab-test --init -y | tee tiup_start_log'),
        systemslab.upload_artifact('tiup_start_log'),
        bash('~/.tiup/bin/tiup cluster display systemslab-test | tee tiup_display_log'),
        systemslab.upload_artifact('tiup_display_log'),
        bash(
          |||
            WAREHOUSES=%s
            PARTITIONS=%s
            DB_PASSWORD=`cat tiup_start_log | grep -oP "(?<=The new password is: ').*(?=')"`
            time ~/.tiup/bin/tiup bench tpcc --warehouses $WAREHOUSES --parts $PARTITIONS prepare -T 8 -H ${TIDB_SERVER_ADDR} -P 4000 -p ${DB_PASSWORD}
          ||| % [warehouses, partitions]
        ),
      ],
    },    
    pd_server: {
      host: {
        tags: ['pingcap', 'i3en-xlarge-1'],         
      },
      steps: [
      ],
    },
    tidb_server: {
      host: {
        tags: ['pingcap', 'i3en-2xlarge-2'],         
      },
      steps : [
      ],
    },
    tikv_server: {
      host: {
        tags: ['pingcap', 'i3en-2xlarge-3'],        
      },
      steps : [
      ],
    },       
  }
}