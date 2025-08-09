#![allow(non_upper_case_globals)]
use std::{
    ffi::{CStr, c_int},
    marker::PhantomData,
};

#[repr(transparent)]
pub struct DartObject<'a> {
    pub(super) raw: RawDartCObject,
    references: PhantomData<&'a ()>,
}

impl<'a> DartObject<'a> {
    pub const NULL: DartObject<'static> = DartObject {
        raw: RawDartCObject {
            type_: Dart_CObject_Type_Dart_CObject_kNull,
            value: RawDartCObjectValue { as_bool: false },
        },
        references: PhantomData,
    };

    pub fn array(elements: &'a mut [&'a DartObject<'a>]) -> Self {
        Self {
            raw: RawDartCObject {
                type_: Dart_CObject_Type_Dart_CObject_kArray,
                value: RawDartCObjectValue {
                    as_array: RawDartCObjectArray {
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
            raw: RawDartCObject {
                type_: Dart_CObject_Type_Dart_CObject_kString,
                value: RawDartCObjectValue {
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
            raw: RawDartCObject {
                type_: Dart_CObject_Type_Dart_CObject_kBool,
                value: RawDartCObjectValue { as_bool: value },
            },
            references: PhantomData,
        }
    }
}

#[repr(C)]
pub struct RawDartCObject {
    pub type_: c_int,
    pub value: RawDartCObjectValue,
}

#[repr(C)]
pub union RawDartCObjectValue {
    pub as_bool: bool,
    pub as_int32: i32,
    pub as_int64: i64,
    pub as_double: f64,
    pub as_string: *const ::core::ffi::c_char,
    //pub as_send_port: _Dart_CObject__bindgen_ty_1__bindgen_ty_1,
    //pub as_capability: _Dart_CObject__bindgen_ty_1__bindgen_ty_2,
    pub as_array: RawDartCObjectArray,
    //pub as_typed_data: _Dart_CObject__bindgen_ty_1__bindgen_ty_4,
    //pub as_external_typed_data: _Dart_CObject__bindgen_ty_1__bindgen_ty_5,
    //pub as_native_pointer: _Dart_CObject__bindgen_ty_1__bindgen_ty_6,
}

#[repr(C)]
#[derive(Clone, Copy)] // to allow use in union
pub struct RawDartCObjectArray {
    pub length: isize,
    pub values: *mut *mut RawDartCObject,
}

pub const Dart_CObject_Type_Dart_CObject_kNull: c_int = 0;
pub const Dart_CObject_Type_Dart_CObject_kBool: c_int = 1;
pub const Dart_CObject_Type_Dart_CObject_kString: c_int = 5;
pub const Dart_CObject_Type_Dart_CObject_kArray: c_int = 6;
