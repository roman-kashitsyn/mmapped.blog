use super::*;

#[test]
#[should_panic(expected = "parser is stuck at offset 0")]
fn repeated_lookups_exhaust_fuel() {
    let mut parser = Parser::new("");
    for _ in 0..=FUEL {
        parser.nth(0);
    }
}

#[test]
#[should_panic(expected = "parser is stuck at offset 0")]
fn empty_nodes_do_not_refill_fuel() {
    let mut parser = Parser::new("");
    for _ in 0..=FUEL {
        let mark = parser.open();
        parser.nth(0);
        parser.close(mark, Group);
    }
}

#[test]
fn consuming_trivia_refills_fuel() {
    let mut parser = Parser::new("% comment");
    parser.fuel = 0;
    assert_eq!(parser.nth(0), Eof);
    assert_eq!(parser.fuel, FUEL - 1);
}
