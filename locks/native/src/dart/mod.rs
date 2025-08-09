mod dl;
mod object;

pub use dl::DartApi;
pub use object::DartObject;

#[repr(transparent)]
pub struct DartPort(i64);

impl DartPort {
    pub fn send<'a>(&self, api: &DartApi, message: &mut DartObject<'a>) -> bool {
        let raw = &mut message.raw;
        let raw = std::ptr::from_mut(raw);

        unsafe { (api.post_object)(self.0, raw) }
    }
}
