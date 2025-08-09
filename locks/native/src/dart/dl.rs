use std::{
    ffi::{CStr, c_char, c_int},
    os::raw::c_void,
};

use crate::dart::object::RawDartCObject;

#[repr(C)]
struct RawDartApiEntry {
    pub name: *const c_char,
    pub function: *const c_void,
}

#[repr(C)]
struct RawDartApi {
    pub major: c_int,
    pub minor: c_int,
    pub functions: *const RawDartApiEntry,
}

pub struct DartApi {
    pub post_object: unsafe extern "C" fn(port_id: i64, message: *mut RawDartCObject) -> bool,
}

impl DartApi {
    pub unsafe fn from_raw(ptr: *const c_void) -> Self {
        let raw = unsafe { (ptr.cast::<RawDartApi>()).as_ref() }.unwrap();

        if raw.major != 2 || raw.minor < 6 {
            panic!("Incompatible Dart embedder, need version ^2.6");
        }

        let mut post_object: Option<PostObjectSignature> = None;

        // See https://github.com/dart-lang/sdk/blob/9f2218e4509210576abecc79d7184c94a3ad0e26/runtime/include/dart_api_dl.c#L23-L30
        let mut entry = raw.functions;
        loop {
            {
                let Some(entry) = (unsafe { entry.as_ref() }) else {
                    break;
                };
                if entry.name.is_null() {
                    break;
                }

                let name = unsafe { CStr::from_ptr(entry.name) };
                let function = entry.function;

                if name == c"Dart_PostCObject" {
                    post_object = unsafe { function.cast::<Option<PostObjectSignature>>().read() };
                }
            }

            entry = unsafe { entry.add(1) };
        }

        Self {
            post_object: post_object.unwrap(),
        }
    }
}

type PostObjectSignature = unsafe extern "C" fn(port_id: i64, message: *mut RawDartCObject) -> bool;
