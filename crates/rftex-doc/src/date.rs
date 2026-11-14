//! Calendar dates.

use std::fmt;

/// A day of the calendar. Dates order chronologically.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct Date {
    pub year: u16,
    /// 1 to 12.
    pub month: u8,
    /// 1 to 31. The day is not checked against the length of the month.
    pub day: u8,
}

impl Date {
    /// The date of documents that do not say when they were written.
    pub const EPOCH: Date = Date {
        year: 1970,
        month: 1,
        day: 1,
    };

    /// Parses `YYYY-MM-DD`.
    pub fn parse(text: &str) -> Option<Date> {
        let bytes = text.as_bytes();
        if bytes.len() != 10 || bytes[4] != b'-' || bytes[7] != b'-' {
            return None;
        }
        let number = |range: std::ops::Range<usize>| -> Option<u16> {
            let digits = &text[range];
            if digits.bytes().all(|byte| byte.is_ascii_digit()) {
                digits.parse().ok()
            } else {
                None
            }
        };
        let (year, month, day) = (number(0..4)?, number(5..7)?, number(8..10)?);
        if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
            return None;
        }
        Some(Date {
            year,
            month: month as u8,
            day: day as u8,
        })
    }

    /// The RFC 3339 timestamp of the midnight that starts the day in UTC.
    pub fn to_rfc3339_midnight(self) -> String {
        format!("{self}T00:00:00Z")
    }
}

/// Formats as `YYYY-MM-DD`.
impl fmt::Display for Date {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:04}-{:02}-{:02}", self.year, self.month, self.day)
    }
}

#[cfg(test)]
mod tests;
