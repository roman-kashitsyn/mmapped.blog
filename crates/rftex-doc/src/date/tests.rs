use super::*;

#[test]
fn parses_and_prints_iso_dates() {
    let date = Date::parse("2025-01-09").unwrap();
    assert_eq!(
        date,
        Date {
            year: 2025,
            month: 1,
            day: 9
        }
    );
    assert_eq!(date.to_string(), "2025-01-09");
    assert_eq!(date.to_rfc3339_midnight(), "2025-01-09T00:00:00Z");
}

#[test]
fn rejects_malformed_dates() {
    for text in [
        "",
        "not-a-date",
        "2025-1-09",
        "2025/01/09",
        "2025-13-01",
        "2025-00-10",
        "2025-01-32",
        "2025-01-00",
        "+025-01-09",
        "2025-01-09 ",
        "２０２５-01-09",
    ] {
        assert_eq!(Date::parse(text), None, "{text:?}");
    }
}

#[test]
fn dates_order_chronologically() {
    let date = |text| Date::parse(text).unwrap();
    assert!(date("2024-12-31") < date("2025-01-01"));
    assert!(date("2025-01-31") < date("2025-02-01"));
    assert!(date("2025-02-01") < date("2025-02-02"));
    assert!(Date::EPOCH < date("2019-01-01"));
}
