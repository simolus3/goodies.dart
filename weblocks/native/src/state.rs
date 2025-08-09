use std::{
    collections::VecDeque,
    ffi::CString,
    rc::Rc,
    sync::{
        Arc,
        atomic::{AtomicU8, Ordering},
    },
};

use crate::{
    LockClient, RequestSnapshot,
    dart::{DartObject, DartPort},
};

pub struct LockRequest {
    pub name: String,
    pub(crate) client: Arc<LockClient>,
    pub shared: bool,
    pub steal: bool,
    pub if_available: bool,
    pub notify: DartPort,
    pub holds_lock: LockRequestState,
}

pub struct LockState {
    pub name: String,
    pending: VecDeque<Arc<LockRequest>>,
    held: Option<HeldLockSet>,
}

struct HeldLockSet {
    shared: bool,
    entries: Vec<Arc<LockRequest>>,
}

impl LockState {
    pub fn new(name: String) -> Self {
        Self {
            name,
            pending: Default::default(),
            held: Default::default(),
        }
    }

    pub fn lock(&mut self, request: Arc<LockRequest>) {
        // Loosely based on https://w3c.github.io/web-locks/#algorithm-request-lock.
        if request.steal {
            if let Some(held) = self.held.take() {
                for entry in held.entries {
                    entry.notify_stolen();
                }
            }

            self.pending.push_front(request);
        } else {
            if request.if_available {
                if !self.is_grantable(request.shared) {
                    request.notify_not_available();
                    return;
                }
            }

            self.pending.push_back(request);
        }

        self.process_queue();
    }

    pub fn clear_request(&mut self, request: &Arc<LockRequest>) {
        if let Some(ref mut held) = self.held {
            held.entries.retain(|r| !Arc::ptr_eq(r, request));
            if held.entries.is_empty() {
                self.held = None;
            }
        }

        self.pending.retain(|r| !Arc::ptr_eq(r, request));
        self.process_queue();
    }

    pub fn is_idle(&self) -> bool {
        return self.held.is_none() && self.pending.is_empty();
    }

    pub fn snapshot_into(&self, into: &mut Vec<RequestSnapshot>) {
        let name = Rc::new(CString::new(self.name.clone()).unwrap());

        for pending in &self.pending {
            into.push(RequestSnapshot {
                name: name.clone(),
                client_id: CString::new(pending.client.name.clone()).unwrap(),
                exclusive: !pending.shared,
                held: false,
            });
        }

        if let Some(active) = &self.held {
            for active in &active.entries {
                into.push(RequestSnapshot {
                    name: name.clone(),
                    client_id: CString::new(active.client.name.clone()).unwrap(),
                    exclusive: !active.shared,
                    held: true,
                });
            }
        }
    }

    fn process_queue(&mut self) {
        while !self.pending.is_empty() {
            let Some(entry) = self.pending.get(0) else {
                break;
            };

            if !self.is_grantable(entry.shared) {
                // If this entry can't be granted, subsequent entries are blocked too.
                break;
            }
            let entry = self.pending.pop_front().unwrap();
            self.add_to_held(entry);
        }
    }

    /// Whether a given request could be granted immediately.
    ///
    /// This is the case if the lock is not currently held, or if a shared request is made while the
    /// lock is held by shared requests.
    fn is_grantable(&mut self, shared: bool) -> bool {
        let Some(held) = &self.held else {
            return true;
        };

        return held.shared && shared;
    }

    fn add_to_held(&mut self, request: Arc<LockRequest>) {
        let held = self.held.get_or_insert_with(|| HeldLockSet {
            shared: request.shared,
            entries: Vec::default(),
        });

        assert!(held.shared == request.shared);
        if request.holds_lock.mark_holds_lock() {
            if request.notify_locked() {
                request.holds_lock.mark_holds_lock();
                held.entries.push(request);
            } else {
                request.holds_lock.reset_locked_bit();
            }
        }
    }
}

impl LockRequest {
    fn notify_locked(&self) -> bool {
        let locked = c"locked".into();
        let mut parts = [&locked];

        self.notify
            .send(&self.client.api, &mut DartObject::array(&mut parts))
    }

    fn notify_stolen(&self) {
        if self.holds_lock.mark_cancelled() {
            let locked = c"stolen".into();
            let mut parts = [&locked];

            self.notify
                .send(&self.client.api, &mut DartObject::array(&mut parts));
        }
    }

    fn notify_not_available(&self) -> bool {
        let locked = c"unavailable".into();
        let mut parts = [&locked];

        self.notify
            .send(&self.client.api, &mut DartObject::array(&mut parts))
    }
}

#[repr(transparent)]
#[derive(Default)]
pub struct LockRequestState(AtomicU8);

impl LockRequestState {
    pub const FLAG_HOLDS_LOCK: u8 = 0x01;
    pub const FLAG_CANCELLED: u8 = 0x02;

    pub fn mark_holds_lock(&self) -> bool {
        let prev = self.0.fetch_or(Self::FLAG_HOLDS_LOCK, Ordering::SeqCst);
        return prev == 0;
    }

    pub fn reset_locked_bit(&self) {
        self.0.fetch_and(!Self::FLAG_HOLDS_LOCK, Ordering::SeqCst);
    }

    pub fn mark_cancelled(&self) -> bool {
        let previous = self.0.fetch_or(Self::FLAG_CANCELLED, Ordering::SeqCst);
        return previous & Self::FLAG_CANCELLED == 0;
    }
}
