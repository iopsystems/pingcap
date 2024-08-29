local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function(sysbench_threads="16", tikv_network_queue="8")
{
  local config = {
    name: "pingcap-network-queue",  
    tiup_tags: ['pingcap', 'c6g-2xlarge-1'],
    tipd_tags: ['pingcap', 'c6g-2xlarge-2'],
    tikv_1_tags: ['pingcap', 'c6g-2xlarge-3'],
    tidb_1_tags: ['pingcap', 'c6g-2xlarge-4'],  
    tidb_2_tags: ['pingcap', 'c6g-2xlarge-5'],  
    tidb_3_tags: ['pingcap', 'c6g-2xlarge-6'],    
    storage: "/mnt/gp3",
    sysbench_threads: std.parseJson(sysbench_threads),
    tikv_network_queue: std.parseJson(tikv_network_queue),
  },
  metadata: config,
  name: config.name,
  jobs: {
    sysbench_client: {
      host: {
        tags: config.tiup_tags,
      },       
      steps: [
        # wait for the TIKV network queue setting
        systemslab.barrier('tikv-network-queue'),
        # run sysbench
        bash(        
          |||
            sleep 2
            SYSBENCH_THREADS=%s
            sysbench --report-interval=1 --percentile=99 --histogram=on --time=60 --config-file=/home/systemslab-agent/config oltp_point_select --threads=$SYSBENCH_THREADS --tables=1 --table-size=100000 --db-ps-mode=auto --rand-type=uniform run | tee sysbench_output.txt
          ||| % [config.sysbench_threads]
        ),
        systemslab.upload_artifact('sysbench_output.txt'),
      ],
    },        
    tikv_1_server: {
      host: {
        tags: config.tikv_1_tags,        
      },
      steps : 
        if config.tikv_network_queue == 1 then [
          bash(        
            |||
              sudo ethtool -L ens5 combined 1
              TIKV_PID=`pgrep tikv`              
              sudo taskset -apc 1-7 $TIKV_PID
            |||
          ),          
          systemslab.barrier('tikv-network-queue'),
        ] else if config.tikv_network_queue == 8 then [
          bash(        
            |||            
              sudo ethtool -L ens5 combined 8
              TIKV_PID=`pgrep tikv`              
              sudo taskset -apc 0-7 $TIKV_PID
            |||
          ),
          systemslab.barrier('tikv-network-queue'),
        ] else [],
    },              
  }
}