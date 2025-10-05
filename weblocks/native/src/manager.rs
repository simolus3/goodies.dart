use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use crate::state::{LockRequest, LockState};

/// A lock manager maintaining multiple locks identified by their name.
#[derive(Default)]
pub struct LockManager {
    /// For simplicity, we use a global mutex. That's not particularly efficient, but this mutex is
    /// only held very briefly while we insert requests into a lock's queue.
    locks: Mutex<HashMap<String, LockState>>,
}

impl LockManager {
    fn lock_state<'a>(
        locks: &'a mut HashMap<String, LockState>,
        name: &String,
    ) -> &'a mut LockState {
        locks
            .entry(name.clone())
            .or_insert_with(|| LockState::new(name.clone()))
    }

    pub fn lock(&self, request: Arc<LockRequest>) {
        let mut locks = self.locks.lock().unwrap();
        let lock = Self::lock_state(&mut locks, &request.name);
        lock.lock(request);
    }

    pub fn close_request(&self, request: Arc<LockRequest>) {
        let mut locks = self.locks.lock().unwrap();
        let lock = Self::lock_state(&mut locks, &request.name);

        if request.holds_lock.mark_cancelled() {
            lock.clear_request(&request);
        }

        if lock.is_idle() {
            locks.remove(&request.name);
        }
    }

    pub fn inspect(&self, mut f: impl FnMut(&LockState)) {
        let locks = self.locks.lock().unwrap();
        for value in locks.values() {
            f(value);
        }
    }
}
