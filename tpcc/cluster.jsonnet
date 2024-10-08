local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function(warehouses=4, partitions=1, threads=1, bench=true)
{
  local config = {
    name: "pingcap-tpcc-cluster",  
    tiup_tags: ['pingcap', 'm7i-2xlarge-1'],
    tikv_tags: ['pingcap', 'm7i-2xlarge-2'],
    tidb_tags: ['pingcap', 'm7i-2xlarge-3'],
    tipd_tags: ['pingcap', 'm7i-2xlarge-4'],
    warehouses: warehouses,
    partitions: partitions,
    threads: threads,
    storage: "/mnt/localssd-1",
    interval: "10s",
    duration: "10s",
    parameters: {
      warehouses: warehouses,
      partitions: partitions,
      threads: threads,
      ec2: 'i3en-2xlarge',
    }
  },
  local topology = {
    global: {
      user: "systemslab-agent",
      ssh_port: 22,
      deploy_dir: config.storage + "/tidb-deploy",
      data_dir: config.storage + "/tidb-data",
      listen_host: "0.0.0.0",
      arch: "amd64",
    },
    pd_servers: [{ host: "PD_SERVER_IP"}],
    monitoring_servers: [{ host: "PD_SERVER_IP"}],
    grafana_servers: [{ host: "PD_SERVER_IP"}],
    tidb_servers: [{ host: "TIDB_SERVER_IP"}],
    tikv_servers: [{ host: "TIKV_SERVER_IP"}],       
  },
  metadata: config,
  name: config.name,
  jobs: {
    tiup_control: {
      host: {
        tags: config.tiup_tags,
      },       
      steps: [
        # cleaning up the data also any remaining tidb processes
        bash(        
          |||
            ~/.tiup/bin/tiup cluster destroy systemslab-test -y || true
          |||
        ),        
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
            cp ./topology.yaml /tmp/topology.yaml
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
            DB_PASSWORD=`cat tiup_start_log | grep -oP "(?<=The new password is: ').*(?=')"`
            echo $DB_PASSWORD > /tmp/tidb_password.txt
          |||
        ),
      ] + (if bench == true then [
        bash(
          |||
            WAREHOUSES=%s
            PARTITIONS=%s
            DURATION=%s
            INTERVAL=%s
            THREADS=%s
            DB_PASSWORD=`cat tiup_start_log | grep -oP "(?<=The new password is: ').*(?=')"`
            time ~/.tiup/bin/tiup bench tpcc --warehouses $WAREHOUSES --parts $PARTITIONS prepare -T 8 -H ${TIDB_SERVER_ADDR} -P 4000 -p ${DB_PASSWORD}
            ~/.tiup/bin/tiup bench tpcc --warehouses $WAREHOUSES --time 60s -H ${TIDB_SERVER_ADDR} -P 4000 -p ${DB_PASSWORD} --output json run | tee tpcc-warmup.json
          ||| % [config.warehouses, config.partitions, config.duration, config.interval, config.threads]
        ),
        systemslab.upload_artifact('tpcc-warmup.json'), 
        systemslab.barrier('tpcc-start'),        
        bash(
          |||
            WAREHOUSES=%s
            PARTITIONS=%s
            DURATION=%s
            INTERVAL=%s
            THREADS=%s
            DB_PASSWORD=`cat tiup_start_log | grep -oP "(?<=The new password is: ').*(?=')"`            
            sleep 22
            ~/.tiup/bin/tiup bench tpcc -T $THREADS --warehouses $WAREHOUSES --time $DURATION --interval $INTERVAL -H ${TIDB_SERVER_ADDR} -P 4000 -p ${DB_PASSWORD} --output json run | tee tpcc.json
          ||| % [config.warehouses, config.partitions, config.duration, config.interval, config.threads]
        ),
        systemslab.upload_artifact('tpcc.json'),
        systemslab.barrier('tpcc-end'),
        bash(
          |||
            ~/.tiup/bin/tiup cluster destroy systemslab-test -y
          |||
        ),
      ] else [])
    },    
    pd_server: {
      host: {
        tags: config.tipd_tags,         
      },
      steps: if bench == true then [        
        systemslab.barrier('tpcc-warmup'),
        bash("du -sh /mnt/localssd-1/tidb-data || true"),
        systemslab.barrier('tpcc-start'),
        systemslab.barrier('tpcc-end'),
      ] else [],
    },
    tidb_server: {
      host: {
        tags: config.tidb_tags,         
      },
      steps : if bench == true then [  
        systemslab.barrier('tpcc-warmup'),
        bash("du -sh /mnt/localssd-1/tidb-data || true"),
        systemslab.barrier('tpcc-start'),
        bash(
          |||            
            sudo pkill tidb-server            
            sudo tshark -f 'tcp port 4000 or tcp port 20160' -w /tmp/tidb.pcap --interface ens5 -a duration:32&
            sleep 20
            date +%s%N > perf_epoch.txt
            sudo perf stat -p `pgrep tidb-server` -e task-clock -I 1 -j -o tidb_perf.json -- sleep 12
            sudo chmod 777 /tmp/tidb.pcap
          |||
        ),
        systemslab.upload_artifact('perf_epoch.txt'),
        systemslab.upload_artifact('tidb_perf.json'),
        systemslab.upload_artifact('/tmp/tidb.pcap'),
        systemslab.barrier('tpcc-end'),       
      ] else []
    },
    tikv_server: {
      host: {
        tags: config.tikv_tags,        
      },
      steps : if bench == true then [
        systemslab.barrier('tpcc-warmup'),
        bash("du -sh /mnt/localssd-1/tidb-data || true"),
        systemslab.barrier('tpcc-start'),
        bash(
          |||
            sleep 20
            date +%s%N > perf_epoch.txt
            sudo perf stat -p `pgrep tikv-server` -e task-clock -I 1 -j -o tikv_perf.json -- sleep 12
          |||
        ), 
        systemslab.upload_artifact('perf_epoch.txt'),
        systemslab.upload_artifact('tikv_perf.json'),
        systemslab.barrier('tpcc-end'),
      ] else []
    },       
  }
}