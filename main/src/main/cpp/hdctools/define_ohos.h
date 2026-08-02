// Local define override for OHOS: use app-sandbox UDS path instead of
// the system /data/hdc/hdc_debug/hdc_server (which system hdcd owns).
#ifndef HDC_DEFINE_OHOS_LOCAL_H
#define HDC_DEFINE_OHOS_LOCAL_H

// Override: app-private UDS socket path
#undef UDS_PATH
#define UDS_PATH "/data/storage/el2/base/haps/entry/temp/hdc_server"

#endif