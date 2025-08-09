use std::{
    ffi::{c_void, CString},
    rc::Rc,
    sync::Arc,
};

use lazy_static::lazy_static;

use crate::{
    dart::{DartApi, DartObject, DartPort},
    manager::LockManager,
    state::LockRequest,
};

mod dart;
mod manager;
mod state;

lazy_static! {
    static ref LOCKS: LockManager = LockManager::default();
}

struct LockClient {
    name: String,
    pub(crate) api: DartApi,
}

struct RequestSnapshot {
    name: Rc<CString>,
    client_id: CString,
    exclusive: bool,
    held: bool,
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_weblocks_client(
    name_length: isize,
    name: *const u8,
    api: *mut c_void,
) -> *const c_void {
    let api = unsafe { DartApi::from_raw(api) };

    let name = unsafe {
        std::str::from_utf8_unchecked(std::slice::from_raw_parts(name, name_length as usize))
    }
    .to_string();

    Arc::into_raw(Arc::new(LockClient { name, api })).cast()
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_weblocks_free_client(ptr: *const c_void) {
    drop(unsafe { Arc::from_raw(ptr.cast::<LockClient>()) });
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_weblocks_obtain(
    name_length: isize,
    name: *const u8,
    client: *const c_void,
    flags: u32,
    port: DartPort,
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
        notify: port,
    });

    LOCKS.lock(request.clone());
    return Arc::into_raw(request).cast();
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_weblocks_unlock(ptr: *mut LockRequest) {
    let request = unsafe { Arc::from_raw(ptr) };
    LOCKS.close_request(request);
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_weblocks_snapshot(client: *const c_void, port: DartPort) {
    let mut descriptions = Vec::<RequestSnapshot>::new();
    LOCKS.inspect(|state| {
        state.snapshot_into(&mut descriptions);
    });

    let mut serialized_descriptions = Vec::<DartObject>::new();
    for description in &descriptions {
        serialized_descriptions.push(DartObject::from(description.name.as_c_str()));
        serialized_descriptions.push(DartObject::from(description.client_id.as_c_str()));
        serialized_descriptions.push(DartObject::from(description.exclusive));
        serialized_descriptions.push(DartObject::from(description.held));
    }

    let mut double_indirection: Vec<&DartObject> =
        serialized_descriptions.iter().map(|r| r).collect();

    let client = unsafe { client.cast::<LockClient>().as_ref() }.unwrap();
    port.send(&client.api, &mut DartObject::array(&mut double_indirection));
}
