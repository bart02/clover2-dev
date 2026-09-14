enable_extension "image-output-qcow2"

#### *run before installing host dependencies*
function add_host_dependencies__ovf_host_deps() {
	EXTRA_BUILD_DEPS+=("qemu::qemu-utils")
}

#### *allow extensions to prepare their own config, after user config is done*
function extension_prepare_config__prepare_ovf_config() {
	declare -g OVF_VM_CPUS="${OVF_VM_CPUS:-4}"        # Number of CPUs
	declare -g OVF_VM_RAM_GB="${OVF_VM_RAM_GB:-4}"    # RAM in Gigabytes
	declare -g OVF_KEEP_QCOW2="${OVF_KEEP_QCOW2:-no}" # Keep the qcow2 image after conversion to OVA
	declare -g OVF_KEEP_IMG="${OVF_KEEP_IMG:-no}"     # Keep the raw image after conversion to OVA

	# OVA is directly importable and must not be wrapped in .xz or .zst.
	local configured_skip_compressing="${SKIP_COMPRESSING:-}"
	local skip_compressing=" ${configured_skip_compressing//,/ } "
	if [[ "${skip_compressing}" != *" ova "* ]]; then
		declare -g SKIP_COMPRESSING="${SKIP_COMPRESSING:+${SKIP_COMPRESSING},}ova"
	fi
}

#### *custom post build hook*
function post_build_image__920_create_ovf() {
	local OVF_VM_NAME="${OVF_VM_NAME:-${version}}"
	local original_qcow2_image="${QCOW2_IMAGE_FILE}"
	local temp_qcow2_image="${DESTIMG}/${version}_temp.qcow2"

	# The name is also used as an XML identifier and as part of archive member names.
	if [[ ! "${OVF_VM_NAME}" =~ ^[A-Za-z0-9._-]+$ ]]; then
		exit_with_error "OVF_VM_NAME contains unsupported characters" "${OVF_VM_NAME}"
	fi

	local base_ova_dirname="${OVF_VM_NAME}_ova"
	local full_ova_dirname="${DESTIMG}/${base_ova_dirname}"
	local base_ovf_file="${OVF_VM_NAME}.ovf"
	local full_ovf_file="${full_ova_dirname}/${base_ovf_file}"
	local base_manifest_file="${OVF_VM_NAME}.mf"
	local full_manifest_file="${full_ova_dirname}/${base_manifest_file}"
	local base_vmdk_file="${OVF_VM_NAME}-disk1-efi-rootfs.vmdk"
	local full_vmdk_file="${full_ova_dirname}/${base_vmdk_file}"
	local final_ova_file="${DESTIMG}/${version}.ova"

	mkdir -p "${full_ova_dirname}"

	display_alert "Converting image to stream-optimized VMDK" "${EXTENSION}" "info"
	run_host_command_logged qemu-img create -f qcow2 -F qcow2 -b "${original_qcow2_image}" "${temp_qcow2_image}"
	run_host_command_logged qemu-img resize "${temp_qcow2_image}" +47G
	run_host_command_logged qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized,compat6 "${temp_qcow2_image}" "${full_vmdk_file}"
	run_host_command_logged rm -vf "${temp_qcow2_image}"

	if [[ "${OVF_KEEP_QCOW2}" != "yes" ]]; then
		display_alert "Discarding qcow2 image after" "conversion to OVA" "debug"
		run_host_command_logged rm -vf "${original_qcow2_image}"
	fi
	if [[ "${OVF_KEEP_IMG}" != "yes" ]]; then
		display_alert "Discarding .img image after" "conversion to OVA" "debug"
		run_host_command_logged rm -vf "${DESTIMG}/${version}.img" "${DESTIMG}/${version}.img.txt"
	fi

	run_host_command_logged qemu-img info "${full_vmdk_file}"

	local disk_capacity_bytes
	disk_capacity_bytes="$(qemu-img info --output=json "${full_vmdk_file}" | sed -nE 's/^[[:space:]]*"virtual-size":[[:space:]]*([0-9]+),?$/\1/p' | tail -n 1)"
	if [[ ! "${disk_capacity_bytes}" =~ ^[0-9]+$ ]]; then
		exit_with_error "Could not determine VMDK virtual size" "${full_vmdk_file}"
	fi

	local vmdk_file_size_bytes
	vmdk_file_size_bytes="$(wc -c < "${full_vmdk_file}" | tr -d '[:space:]')"

	display_alert "Creating OVF descriptor" "${EXTENSION}" "info"
	cat <<- OVF_FILE > "${full_ovf_file}"
		<?xml version="1.0" encoding="UTF-8"?>
		<Envelope
		  xmlns="http://schemas.dmtf.org/ovf/envelope/1"
		  xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
		  xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
		  xmlns:vmw="http://www.vmware.com/schema/ovf"
		  xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData">
		  <References>
		    <File ovf:href="${base_vmdk_file}" ovf:id="file1" ovf:size="${vmdk_file_size_bytes}"/>
		  </References>
		  <DiskSection>
		    <Info>Virtual disk information</Info>
		    <Disk ovf:capacity="${disk_capacity_bytes}" ovf:capacityAllocationUnits="byte"
		      ovf:diskId="vmdisk1" ovf:fileRef="file1"
		      ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
		  </DiskSection>
		  <NetworkSection>
		    <Info>Logical networks</Info>
		    <Network ovf:name="nat"><Description>NAT network</Description></Network>
		  </NetworkSection>
		  <VirtualSystem ovf:id="${OVF_VM_NAME}">
		    <Info>Armbian virtual machine</Info>
		    <Name>${OVF_VM_NAME}</Name>
		    <OperatingSystemSection ovf:id="94" vmw:osType="ubuntu-64">
		      <Info>Guest operating system</Info>
		      <Description>Ubuntu 64-bit</Description>
		    </OperatingSystemSection>
		    <VirtualHardwareSection>
		      <Info>Virtual hardware requirements</Info>
		      <System>
		        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
		        <vssd:InstanceID>0</vssd:InstanceID>
		        <vssd:VirtualSystemIdentifier>${OVF_VM_NAME}</vssd:VirtualSystemIdentifier>
		        <vssd:VirtualSystemType>vmx-18</vssd:VirtualSystemType>
		      </System>
		      <Item>
		        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
		        <rasd:Description>Number of virtual CPUs</rasd:Description>
		        <rasd:ElementName>${OVF_VM_CPUS} virtual CPU(s)</rasd:ElementName>
		        <rasd:InstanceID>1</rasd:InstanceID>
		        <rasd:ResourceType>3</rasd:ResourceType>
		        <rasd:VirtualQuantity>${OVF_VM_CPUS}</rasd:VirtualQuantity>
		      </Item>
		      <Item>
		        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
		        <rasd:Description>Memory Size</rasd:Description>
		        <rasd:ElementName>${OVF_VM_RAM_GB}GB of memory</rasd:ElementName>
		        <rasd:InstanceID>2</rasd:InstanceID>
		        <rasd:ResourceType>4</rasd:ResourceType>
		        <rasd:VirtualQuantity>$((OVF_VM_RAM_GB * 1024))</rasd:VirtualQuantity>
		      </Item>
		      <Item>
		        <rasd:Address>0</rasd:Address>
		        <rasd:Description>SCSI Controller</rasd:Description>
		        <rasd:ElementName>SCSI controller 0</rasd:ElementName>
		        <rasd:InstanceID>3</rasd:InstanceID>
		        <rasd:ResourceSubType>VirtualSCSI</rasd:ResourceSubType>
		        <rasd:ResourceType>6</rasd:ResourceType>
		        <vmw:Config ovf:required="false" vmw:key="virtualDev" vmw:value="pvscsi"/>
		      </Item>
		      <Item>
		        <rasd:AddressOnParent>0</rasd:AddressOnParent>
		        <rasd:ElementName>Hard disk 1</rasd:ElementName>
		        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
		        <rasd:InstanceID>4</rasd:InstanceID>
		        <rasd:Parent>3</rasd:Parent>
		        <rasd:ResourceType>17</rasd:ResourceType>
		      </Item>
		      <Item>
		        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
		        <rasd:Connection>nat</rasd:Connection>
		        <rasd:Description>VMXNET3 ethernet adapter</rasd:Description>
		        <rasd:ElementName>Ethernet adapter 1</rasd:ElementName>
		        <rasd:InstanceID>5</rasd:InstanceID>
		        <rasd:ResourceSubType>VMXNET3</rasd:ResourceSubType>
		        <rasd:ResourceType>10</rasd:ResourceType>
		      </Item>
		      <vmw:Config ovf:required="false" vmw:key="firmware" vmw:value="efi"/>
		      <vmw:Config ovf:required="false" vmw:key="vcpu.hotadd" vmw:value="true"/>
		      <vmw:Config ovf:required="false" vmw:key="mem.hotadd" vmw:value="true"/>
		    </VirtualHardwareSection>
		  </VirtualSystem>
		</Envelope>
	OVF_FILE

	local ovf_sha256 vmdk_sha256
	ovf_sha256="$(sha256sum "${full_ovf_file}" | awk '{print $1}')"
	vmdk_sha256="$(sha256sum "${full_vmdk_file}" | awk '{print $1}')"
	cat <<- MANIFEST_FILE > "${full_manifest_file}"
		SHA256(${base_ovf_file})= ${ovf_sha256}
		SHA256(${base_vmdk_file})= ${vmdk_sha256}
	MANIFEST_FILE

	display_alert "Creating OVA appliance" "${EXTENSION}" "info"
	run_host_command_logged tar --format=ustar -cf "${final_ova_file}" -C "${full_ova_dirname}" \
		"${base_ovf_file}" "${base_manifest_file}" "${base_vmdk_file}"

	display_alert "Done, cleaning up" "${EXTENSION}" "info"
	rm -rf "${full_ova_dirname}"
	return 0
}
