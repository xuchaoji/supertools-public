// libusb_stubs.cpp — OHOS link-time stubs for libusb.
// USB is not available on OHOS (UDS replaces it), but host_usb.cpp references
// HdcHostUSB which is instantiated in server.cpp, so we need linkable stubs.
// NOTE: libusb_fill_* are static inline in the real header, do not redefine them.
#include <sys/time.h>
#include <cstdlib>
#include <cstring>
#include "libusb.h"

extern "C" {

int libusb_init(libusb_context **ctx) { *ctx = nullptr; return LIBUSB_ERROR_OTHER; }
void libusb_exit(libusb_context *ctx) { (void)ctx; }

uint8_t libusb_get_bus_number(libusb_device *dev) { (void)dev; return 0; }
uint8_t libusb_get_device_address(libusb_device *dev) { (void)dev; return 0; }

int libusb_open(libusb_device *dev, libusb_device_handle **handle) { (void)dev; *handle = nullptr; return LIBUSB_ERROR_NO_DEVICE; }
void libusb_close(libusb_device_handle *dh) { (void)dh; }
int libusb_release_interface(libusb_device_handle *dh, int iface) { (void)dh; (void)iface; return LIBUSB_ERROR_NO_DEVICE; }

int libusb_claim_interface(libusb_device_handle *dh, int iface) { (void)dh; (void)iface; return LIBUSB_ERROR_NO_DEVICE; }
int libusb_set_interface_alt_setting(libusb_device_handle *dh, int iface, int alt) { (void)dh; (void)iface; (void)alt; return LIBUSB_ERROR_NO_DEVICE; }
int libusb_reset_device(libusb_device_handle *dh) { (void)dh; return LIBUSB_ERROR_NO_DEVICE; }
int libusb_kernel_driver_active(libusb_device_handle *dh, int iface) { (void)dh; (void)iface; return 0; }
int libusb_detach_kernel_driver(libusb_device_handle *dh, int iface) { (void)dh; (void)iface; return 0; }
int libusb_set_auto_detach_kernel_driver(libusb_device_handle *dh, int enable) { (void)dh; (void)enable; return 0; }
int libusb_attach_kernel_driver(libusb_device_handle *dh, int iface) { (void)dh; (void)iface; return 0; }

libusb_device *libusb_ref_device(libusb_device *dev) { return dev; }
void libusb_unref_device(libusb_device *dev) { (void)dev; }

int libusb_get_device_descriptor(libusb_device *dev, libusb_device_descriptor *desc) { (void)dev; (void)desc; return LIBUSB_ERROR_NO_DEVICE; }
int libusb_get_active_config_descriptor(libusb_device *dev, libusb_config_descriptor **config) { (void)dev; *config = nullptr; return LIBUSB_ERROR_NO_DEVICE; }
void libusb_free_config_descriptor(libusb_config_descriptor *config) { free(config); }

int libusb_get_string_descriptor_ascii(libusb_device_handle *dh, uint8_t index, unsigned char *data, int len) {
    (void)dh; (void)index; if (data && len > 0) data[0] = 0; return 0;
}
int libusb_get_port_numbers(libusb_device *dev, uint8_t *pn, int pn_len) { (void)dev; (void)pn; (void)pn_len; return 0; }
uint8_t libusb_get_port_number(libusb_device *dev) { (void)dev; return 0; }
int libusb_get_device_speed(libusb_device *dev) { (void)dev; return 0; }
int libusb_get_max_packet_size(libusb_device *dev, unsigned char ep) { (void)dev; (void)ep; return 512; }

ssize_t libusb_get_device_list(libusb_context *ctx, libusb_device ***list) { (void)ctx; *list = nullptr; return 0; }
void libusb_free_device_list(libusb_device **list, int unref_devices) { (void)unref_devices; free(list); }

int libusb_control_transfer(libusb_device_handle *dh, uint8_t bm, uint8_t br, uint16_t wv, uint16_t wi,
                             unsigned char *data, uint16_t wl, unsigned int to) {
    (void)dh; (void)bm; (void)br; (void)wv; (void)wi; (void)data; (void)wl; (void)to; return LIBUSB_ERROR_IO;
}
int libusb_bulk_transfer(libusb_device_handle *dh, unsigned char ep, unsigned char *data, int len,
                          int *transferred, unsigned int to) {
    (void)dh; (void)ep; (void)data; (void)len; (void)to;
    if (transferred) *transferred = 0; return LIBUSB_ERROR_IO;
}
int libusb_interrupt_transfer(libusb_device_handle *dh, unsigned char ep, unsigned char *data, int len,
                               int *transferred, unsigned int to) {
    (void)dh; (void)ep; (void)data; (void)len; (void)to;
    if (transferred) *transferred = 0; return LIBUSB_ERROR_IO;
}

struct libusb_transfer *libusb_alloc_transfer(int iso_packets) {
    (void)iso_packets;
    return (struct libusb_transfer *)calloc(1, sizeof(struct libusb_transfer));
}
void libusb_free_transfer(struct libusb_transfer *t) { free(t); }

int libusb_submit_transfer(struct libusb_transfer *t) {
    if (t && t->callback) t->callback(t);
    return LIBUSB_ERROR_IO;
}
int libusb_cancel_transfer(struct libusb_transfer *t) { (void)t; return LIBUSB_ERROR_NOT_FOUND; }

int libusb_handle_events(libusb_context *ctx) { (void)ctx; return 0; }
int libusb_handle_events_completed(libusb_context *ctx, int *completed) { (void)ctx; if (completed) *completed = 0; return 0; }
int libusb_handle_events_timeout(libusb_context *ctx, struct timeval *tv) { (void)ctx; (void)tv; return 0; }
int libusb_handle_events_timeout_completed(libusb_context *ctx, struct timeval *tv, int *completed) {
    (void)ctx; (void)tv; if (completed) *completed = 0; return 0;
}
int libusb_has_capability(uint32_t cap) { (void)cap; return 0; }

const char *libusb_error_name(int errcode) { (void)errcode; return "LIBUSB_ERROR_OTHER"; }
const char *libusb_strerror(int errcode) { (void)errcode; return "libusb stub (OHOS)"; }

void libusb_set_log_cb(libusb_context *ctx, libusb_log_cb cb, int mode) { (void)ctx; (void)cb; (void)mode; }

// NOTE: libusb_fill_control_transfer / libusb_fill_bulk_transfer are static inline in the header,
// do not redefine here — they will be inlined at each call site.

// Match real header signature: int LIBUSB_CALLV libusb_set_option(libusb_context*, enum libusb_option, ...)
int libusb_set_option(libusb_context *ctx, enum libusb_option option, ...) { (void)ctx; (void)option; return 0; }

// Match real header signature: void LIBUSB_CALL libusb_set_debug(libusb_context*, int)
void libusb_set_debug(libusb_context *ctx, int level) { (void)ctx; (void)level; }

int libusb_hotplug_register_callback(libusb_context *ctx, int events, int flags, int vid, int pid, int cls,
                                      libusb_hotplug_callback_fn cb, void *user, libusb_hotplug_callback_handle *handle) {
    (void)ctx; (void)events; (void)flags; (void)vid; (void)pid; (void)cls; (void)cb; (void)user;
    if (handle) *handle = 0; return 0;
}
void libusb_hotplug_deregister_callback(libusb_context *ctx, libusb_hotplug_callback_handle handle) { (void)ctx; (void)handle; }

} // extern "C"
