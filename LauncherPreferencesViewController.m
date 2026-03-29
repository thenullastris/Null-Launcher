- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"Zenith Launcher 2.0-development\n\nI\uOS: %@ on %@\nPID: %@\nProudly built in Cambodia 🇰🇭\nCreated by ReaperZxMC", [[UIDevice currentDevice] systemVersion], [[UIDevice currentDevice] model], [[NSProcessInfo processInfo] processIdentifier]];
}