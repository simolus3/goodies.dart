mod dl;
mod object;

pub use dl::DartApi;
pub use object::DartObject;

/// A wrapper around a native `SendPort`.
#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(transparent)]
pub struct DartPort(i64);

impl DartPort {
    /// Sends a `message` to this port.
    ///
    /// Returns true if the external contents in `message` have been moved to Dart, false otherwise.
    pub fn send<'a>(&self, api: &DartApi, message: &mut DartObject<'a>) -> bool {
        let raw = &mut message.raw;
        let raw = std::ptr::from_mut(raw);

        unsafe { (api.post_object)(self.0, raw) }
    }
}
