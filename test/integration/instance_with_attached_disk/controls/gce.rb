# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

project_id = attribute('project_id')
zone = attribute('zone')
instance_name = attribute('instance_name')
network = attribute('network')
subnetwork = attribute('subnetwork')
image = attribute('image')
restart_policy = attribute('restart_policy')
machine_type = attribute('machine_type')
vm_container_label = attribute('vm_container_label')

control "gce" do
  title "Google Compute Engine instance configuration"

  describe command("gcloud --project=#{project_id} compute instances describe #{instance_name} --zone=#{zone} --format json") do
    its('exit_status') { should be 0 }
    its('stderr') { should eq '' }

    let!(:metadata) do
      if subject.exit_status == 0
        JSON.parse(subject.stdout)
      else
        {}
      end
    end

    let(:container_declaration) do
      YAML.load(metadata['metadata']['items'].select { |h| h['key'] == 'gce-container-declaration' }.first['value'].gsub("\t", "  "))
    end

    it "is in a running state" do
      expect(metadata['status']).to eq 'RUNNING'
    end

    it "is in the correct network" do
      expect(metadata['networkInterfaces'][0]['network']).to end_with network
    end

    it "is in the correct subnetwork" do
      expect(metadata['networkInterfaces'][0]['subnetwork']).to end_with subnetwork
    end

    it "is the expected machine type" do
      expect(metadata['machineType']).to end_with machine_type
    end

    it "has the expected labels" do
      expect(metadata['labels'].keys).to include "container-vm"
      expect(metadata['labels']['container-vm']).to eq vm_container_label
    end

    it "is configured with the expected container(s), volumes, and restart policy" do
      expect(container_declaration).to eq({
        "spec" => {
          "containers" => [
            {
              "image" => image,
              "volumeMounts" => [
                {
                  "mountPath" => "/cache",
                  "name" => "tempfs-0",
                  "readOnly" => false,
                },
                {
                  "mountPath" => "/persistent-data",
                  "name" => "data-disk-0",
                  "readOnly" => false,
                },
              ],
            },
          ],
          "restartPolicy" => restart_policy,
          "volumes" => [
            {
              "name" => "tempfs-0",
              "emptyDir" => {
                "medium" => "Memory",
              },
            },
            {
              "name" => "data-disk-0",
              "gcePersistentDisk" => {
                "pdName" => "data-disk-0",
                "fsType" => "ext4",
              },
            },
          ],
        },
      })
    end
  end

  describe command("gcloud --project=#{project_id} compute disks list --filter=\"zone:( #{zone} )\" --format json") do
    its('exit_status') { should be 0 }
    its('stderr') { should eq '' }

    let!(:metadata) do
      if subject.exit_status == 0
        JSON.parse(subject.stdout)
      else
        {}
      end
    end

    let(:created_disk_metadata) { metadata.select { |m| m['name'] == "simple-instance-data-disk" }.first }

    it "exists" do
      expect(created_disk_metadata).not_to be_nil
    end

    it "creates and attaches a disk to the instance" do
      expect(created_disk_metadata).to include({
        "name" => "simple-instance-data-disk",
        "sizeGb" => "10",
        "status" => "READY",
        "type" => "https://www.googleapis.com/compute/v1/projects/#{project_id}/zones/#{zone}/diskTypes/pd-ssd",
        "users" => ["https://www.googleapis.com/compute/v1/projects/#{project_id}/zones/#{zone}/instances/#{instance_name}"],
        "zone" => "https://www.googleapis.com/compute/v1/projects/#{project_id}/zones/#{zone}"
      })
    end
  end
end