local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function()
{
  name: 'test',
  jobs: {
    shell: {
      host: {
        tags: ["pingcap"],    
      },
      steps: [
        bash(
          |||        
            nslookup shell.systemslab.internal || true
            ping shell.systemslab.internal || true
          |||
        ),
      ]
    }
  }
}