enable_extension "image-output-compressed-qcow2" # Enable the qcow2 output image extension


function extension_prepare_config__prepare_utm_config() {
	display_alert "Preparing UTM (QEMU) extra packages..." "${EXTENSION}" "info"
	# Add UTM (QEMU) utilities, for all
	add_packages_to_image spice-vdagent qemu-guest-agent
}
