use std::{
    ffi::{CStr, c_char, c_int},
    os::raw::c_void,
};

use crate::dart::object::RawDartCObject;

/// The `DartApiEntry` [C struct](https://github.com/dart-lang/sdk/blob/9f2218e4509210576abecc79d7184c94a3ad0e26/runtime/include/internal/dart_api_dl_impl.h#L10-L13).
#[repr(C)]
struct RawDartApiEntry {
    pub name: *const c_char,
    pub function: *const c_void,
}

/// The `DartApi` struct from `sdk/runtime/include/internal/dart_api_dl_impl.h`
///
/// For the C struct, see [this source](https://github.com/dart-lang/sdk/blob/9f2218e4509210576abecc79d7184c94a3ad0e26/runtime/include/internal/dart_api_dl_impl.h#L15-L19).
#[repr(C)]
struct RawDartApi {
    pub major: c_int,
    pub minor: c_int,
    pub functions: *const RawDartApiEntry,
}

/// A subset of the dynamically-linked Dart API used in this crate.
///
/// Instead of calling DartDL functions as global functions, it's easier for us to load the symbols
/// whenever we have a new lock client.
pub struct DartApi {
    /// Posts a Dart object constructed in native code to a `SendPort` identified by its native id.
    ///
    /// Returns `true` if the send operation has been successful, meaning that ownership of external
    /// data refrenced in `message` has been moved to Dart.
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

                if name == c"Dart_PostCObject" {
                    let ptr: PostObjectSignature = unsafe { std::mem::transmute(entry.function) };
                    post_object = Some(ptr);
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
