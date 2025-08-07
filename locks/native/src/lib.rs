use std::{
    ffi::{CString, c_void},
    rc::Rc,
    sync::{Arc, atomic::AtomicBool},
};

use dart_sys::{Dart_InitializeApiDL, Dart_Port_DL};
use lazy_static::lazy_static;

use crate::{
    dart::{DartObject, DartPort},
    manager::LockManager,
    state::LockRequest,
};

mod dart;
mod manager;
mod state;

lazy_static! {
    static ref LOCKS: LockManager = LockManager::default();
    static ref HAS_INITIALIZED_DL: AtomicBool = AtomicBool::new(false);
}

struct LockClient {
    name: String,
}

struct RequestSnapshot {
    name: Rc<CString>,
    clientId: CString,
    exclusive: bool,
    held: bool,
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_locks_client(
    name_length: isize,
    name: *const u8,
    api: *mut c_void,
) -> *const c_void {
    if !HAS_INITIALIZED_DL.fetch_or(true, std::sync::atomic::Ordering::SeqCst) {
        let res = unsafe { Dart_InitializeApiDL(api) };
        if res != 0 {
            panic!("Dart_InitializeApiDL returned {res}")
        }
    }

    let name = unsafe {
        std::str::from_utf8_unchecked(std::slice::from_raw_parts(name, name_length as usize))
    }
    .to_string();

    Arc::into_raw(Arc::new(LockClient { name })).cast()
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_locks_free_client(ptr: *const c_void) {
    drop(unsafe { Arc::from_raw(ptr.cast::<LockClient>()) });
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_locks_obtain(
    name_length: isize,
    name: *const u8,
    client: *const c_void,
    flags: u32,
    port: Dart_Port_DL,
) -> *const c_void {
    const FLAG_SHARED: u32 = 0x01;
    const FLAG_STEAL: u32 = 0x02;
    const FLAG_IF_AVAILABLE: u32 = 0x04;

    let name = unsafe {
        std::str::from_utf8_unchecked(std::slice::from_raw_parts(name, name_length as usize))
    }
    .to_string();

    let client = client.cast::<LockClient>();
    unsafe { Arc::increment_strong_count(client) };
    let client = unsafe { Arc::from_raw(client) };

    let request = Arc::new(LockRequest {
        name,
        client,
        shared: (flags & FLAG_SHARED) != 0,
        steal: (flags & FLAG_STEAL) != 0,
        if_available: (flags & FLAG_IF_AVAILABLE) != 0,
        holds_lock: Default::default(),
        notify: DartPort::from(port),
    });

    LOCKS.lock(request.clone());
    return Arc::into_raw(request).cast();
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_locks_unlock(ptr: *mut LockRequest) {
    let request = unsafe { Arc::from_raw(ptr) };
    LOCKS.close_request(request);
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_locks_snapshot(port: DartPort) {
    let mut descriptions = Vec::<RequestSnapshot>::new();
    LOCKS.inspect(|state| {
        state.snapshot_into(&mut descriptions);
    });

    let mut serialized_descriptions = Vec::<DartObject>::new();
    for description in &descriptions {
        serialized_descriptions.push(DartObject::from(description.name.as_c_str()));
        serialized_descriptions.push(DartObject::from(description.clientId.as_c_str()));
        serialized_descriptions.push(DartObject::from(description.exclusive));
        serialized_descriptions.push(DartObject::from(description.held));
    }

    let mut double_indirection: Vec<&DartObject> =
        serialized_descriptions.iter().map(|r| r).collect();

    port.send(&mut DartObject::array(&mut double_indirection));
}
