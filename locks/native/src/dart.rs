use std::{ffi::CStr, marker::PhantomData};

use dart_sys::{
    Dart_CObject, Dart_CObject_Type_Dart_CObject_kArray, Dart_CObject_Type_Dart_CObject_kBool,
    Dart_CObject_Type_Dart_CObject_kNull, Dart_CObject_Type_Dart_CObject_kString, Dart_Port_DL,
    Dart_PostCObject_DL,
};

#[repr(transparent)]
pub struct DartPort(Dart_Port_DL);

impl From<Dart_Port_DL> for DartPort {
    fn from(value: Dart_Port_DL) -> Self {
        return Self(value);
    }
}

impl DartPort {
    pub fn send<'a>(&self, message: &mut DartObject<'a>) -> bool {
        let raw = &mut message.raw;
        let raw = std::ptr::from_mut(raw);

        unsafe { Dart_PostCObject_DL.unwrap_unchecked()(self.0, raw) }
    }
}

#[repr(transparent)]
pub struct DartObject<'a> {
    raw: Dart_CObject,
    references: PhantomData<&'a ()>,
}

impl<'a> DartObject<'a> {
    pub const NULL: DartObject<'static> = DartObject {
        raw: Dart_CObject {
            type_: Dart_CObject_Type_Dart_CObject_kNull,
            value: dart_sys::_Dart_CObject__bindgen_ty_1 { as_bool: false },
        },
        references: PhantomData,
    };

    pub fn array(elements: &'a mut [&'a DartObject<'a>]) -> Self {
        Self {
            raw: Dart_CObject {
                type_: Dart_CObject_Type_Dart_CObject_kArray,
                value: dart_sys::_Dart_CObject__bindgen_ty_1 {
                    as_array: dart_sys::_Dart_CObject__bindgen_ty_1__bindgen_ty_3 {
                        length: elements.len() as isize,
                        // This cast is safe because references are pointers at runtime, and since
                        // DartObject is a repr(transparent) wrapper around Dart_CObject.
                        values: elements.as_mut_ptr().cast(),
                    },
                },
            },
            references: PhantomData,
        }
    }
}

impl<'a> From<&'a CStr> for DartObject<'a> {
    fn from(value: &'a CStr) -> Self {
        Self {
            raw: Dart_CObject {
                type_: Dart_CObject_Type_Dart_CObject_kString,
                value: dart_sys::_Dart_CObject__bindgen_ty_1 {
                    as_string: value.as_ptr(),
                },
            },
            references: PhantomData,
        }
    }
}

impl From<bool> for DartObject<'static> {
    fn from(value: bool) -> Self {
        Self {
            raw: Dart_CObject {
                type_: Dart_CObject_Type_Dart_CObject_kBool,
                value: dart_sys::_Dart_CObject__bindgen_ty_1 { as_bool: value },
            },
            references: PhantomData,
        }
    }
}
