use std::{
    cell::Cell,
    collections::HashMap,
    ffi::{CStr, c_char, c_void},
    sync::{Arc, Mutex, Weak},
};

use lazy_static::lazy_static;

use crate::{
    LockClient,
    dart::{DartObject, DartPort},
};

lazy_static! {
    /// All currently-active channels.
    static ref CHANNELS: Mutex<HashMap<String, Weak<BroadcastChannel>>> = Mutex::new(HashMap::new());
}

struct BroadcastChannel {
    self_: Cell<Option<Weak<Self>>>,
    name: String,
    clients: Mutex<Vec<BroadcastChannelClient>>,
}

/// The only non-Sync field is the [Cell], which is only accessed on instantiation and
/// when the channels is dropped.
unsafe impl Sync for BroadcastChannel {}

impl BroadcastChannel {
    fn lookup(name: &str) -> Arc<Self> {
        let mut channels = CHANNELS.lock().unwrap();
        if let Some(existing) = channels.get(name) {
            if let Some(channel) = existing.upgrade() {
                return channel;
            }
        };

        let channel = Self {
            self_: Cell::new(None),
            name: name.to_string(),
            clients: Mutex::default(),
        };
        let channel = Arc::new(channel);
        let weak_channel = Arc::downgrade(&channel);
        channels.insert(channel.name.clone(), weak_channel.clone());
        channel.self_.set(Some(weak_channel));
        channel
    }

    /// Insert a new client to notify for subsequent broadcast messages.
    fn insert_client(&self, client: BroadcastChannelClient) {
        let mut clients = self.clients.lock().unwrap();
        clients.push(client);
    }

    /// Removes a client to no longer notify it.
    fn remove_client(&self, client: &BroadcastChannelClient) {
        let mut clients = self.clients.lock().unwrap();
        clients.retain(|c| c != client);
    }

    fn send_message(&self, sender: &BroadcastChannelClient, msg: &CStr) {
        let clients = self.clients.lock().unwrap();
        let mut dart_msg = DartObject::from(msg);

        for client in &*clients {
            if client != sender {
                client.port.send(&client.client.api, &mut dart_msg);
            }
        }
    }
}

impl Drop for BroadcastChannel {
    fn drop(&mut self) {
        // When all references to a broadcast channel are dropped, remove it from the global map of
        // named channels as well.
        // There's a potential race between the last channel with a name being dropped and a channel
        // with the same name being created concurrently. In this case, we must not remove the map's
        // entry.
        let mut channels = CHANNELS.lock().unwrap();
        if let Some(channel) = channels.get(&self.name) {
            if let Some(key) = self.self_.take() {
                if Weak::ptr_eq(&key, channel) {
                    channels.remove(&self.name);
                }
            }
        }
    }
}

#[derive(Clone)]
struct BroadcastChannelClient {
    /// A client.
    client: Arc<LockClient>,
    /// The Dart port to send broadcast messages to.
    port: DartPort,
}

impl PartialEq for BroadcastChannelClient {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.client, &other.client) && self.port == other.port
    }
}

struct BroadcastChannelReference {
    channel: Arc<BroadcastChannel>,
    client: BroadcastChannelClient,
}

impl BroadcastChannelReference {
    fn send(&self, message: &CStr) {
        self.channel.send_message(&self.client, message);
    }
}

impl Drop for BroadcastChannelReference {
    fn drop(&mut self) {
        self.channel.remove_client(&self.client);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_weblocks_broadcast_channel_new(
    name_length: isize,
    name: *const u8,
    client: *const c_void,
    port: DartPort,
) -> *const c_void {
    let client = unsafe {
        // Safety: Dart should only pass valid pointers.
        LockClient::increment_from_raw(client)
    };

    let name = unsafe {
        std::str::from_utf8_unchecked(std::slice::from_raw_parts(name, name_length as usize))
    };

    let client = BroadcastChannelClient { client, port };
    let channel = BroadcastChannel::lookup(name);
    channel.insert_client(client.clone());

    Box::into_raw(Box::new(BroadcastChannelReference { channel, client })).cast()
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_weblocks_broadcast_channel_free(channel_ref: *mut c_void) {
    drop(unsafe { Box::from_raw(channel_ref as *mut BroadcastChannelReference) })
}

#[unsafe(no_mangle)]
pub extern "C" fn pkg_weblocks_broadcast_channel_send(
    channel_ref: *mut c_void,
    msg: *const c_char,
) {
    let msg = unsafe { CStr::from_ptr(msg) };
    let channel_ref = unsafe {
        // Safety: Dart will pass a pointer valid for the duration of this call.
        (channel_ref as *mut BroadcastChannelReference)
            .as_ref()
            .unwrap_unchecked()
    };

    channel_ref.send(msg);
}
