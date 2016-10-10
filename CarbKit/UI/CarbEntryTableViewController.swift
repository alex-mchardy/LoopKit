//
//  CarbEntryTableViewController.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit

private let ReuseIdentifier = "CarbEntry"


public final class CarbEntryTableViewController: UITableViewController {

    @IBOutlet var unavailableMessageView: UIView!

    @IBOutlet var authorizationRequiredMessageView: UIView!

    @IBOutlet weak var COBValueLabel: UILabel!

    @IBOutlet weak var COBDateLabel: UILabel!

    @IBOutlet weak var totalValueLabel: UILabel!

    @IBOutlet weak var totalDateLabel: UILabel!

    public var carbStore: CarbStore? {
        didSet {
            if let carbStore = carbStore {
                carbStoreObserver = NotificationCenter.default.addObserver(forName: nil,
                    object: carbStore,
                    queue: OperationQueue.main,
                    using: { [weak self] (note) -> Void in
                        switch note.name {
                        case Notification.Name.CarbEntriesDidUpdate:
                            if let strongSelf = self, strongSelf.isViewLoaded {
                                strongSelf.reloadData()
                            }
                        case Notification.Name.StoreAuthorizationStatusDidChange:
                            break
                        default:
                            break
                        }
                    }
                )
            }
        }
    }

    private var updateTimer: Timer? {
        willSet {
            if let timer = updateTimer {
                timer.invalidate()
            }
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        if let carbStore = carbStore {
            if carbStore.authorizationRequired {
                state = .authorizationRequired
            } else if carbStore.sharingDenied {
                state = .unavailable
            } else {
                state = .display
            }
        } else {
            state = .unavailable
        }

        navigationItem.rightBarButtonItems?.append(editButtonItem)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTimelyStats(nil)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let updateInterval = TimeInterval(minutes: 5)
        let timer = Timer(
            fireAt: Date().dateCeiledToTimeInterval(updateInterval).addingTimeInterval(2),
            interval: updateInterval,
            target: self,
            selector: #selector(updateTimelyStats(_:)),
            userInfo: nil,
            repeats: true
        )
        updateTimer = timer

        RunLoop.current.add(timer, forMode: RunLoopMode.defaultRunLoopMode)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        updateTimer = nil
    }

    deinit {
        carbStoreObserver = nil
    }

    // MARK: - Data

    private var carbEntries: [CarbEntry] = []

    private enum State {
        case unknown
        case unavailable
        case authorizationRequired
        case display
    }

    private var state = State.unknown {
        didSet {
            if isViewLoaded {
                reloadData()
            }
        }
    }

    private func reloadData() {
        switch state {
        case .unknown:
            break
        case .unavailable:
            tableView.backgroundView = unavailableMessageView
        case .authorizationRequired:
            tableView.backgroundView = authorizationRequiredMessageView
        case .display:
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }

            tableView.backgroundView = nil
            tableView.tableHeaderView?.isHidden = false
            tableView.tableFooterView = nil

            carbStore?.getRecentCarbEntries { (entries, error) -> Void in
                DispatchQueue.main.async {
                    if let error = error {
                        self.presentAlertController(with: error)
                    } else {
                        self.carbEntries = entries
                        self.tableView.reloadData()
                    }
                }

                self.updateTimelyStats(nil)
                self.updateTotal()
            }
        }
    }

    @objc func updateTimelyStats(_: Timer?) {
        updateCOB()
    }

    private func updateCOB() {
        if case .display = state, let carbStore = carbStore {
            carbStore.carbsOnBoardAtDate(Date(), resultHandler: { (value, error) -> Void in
                DispatchQueue.main.async {
                    if let value = value {
                        self.COBValueLabel.text = NumberFormatter.localizedString(from: NSNumber(value: value.quantity.doubleValue(for: carbStore.preferredUnit)), number: .none)
                        self.COBDateLabel.text = String(format: NSLocalizedString("com.loudnate.CarbKit.COBDateLabel", tableName: "CarbKit", value: "at %1$@", comment: "The format string describing the date of a COB value. The first format argument is the localized date."), DateFormatter.localizedString(from: value.startDate, dateStyle: .none, timeStyle: .short))
                    } else {
                        self.COBValueLabel.text = NumberFormatter.localizedString(from: 0, number: .none)
                        self.COBDateLabel.text = nil
                    }
                }
            })
        }
    }

    private func updateTotal() {
        if case .display = state, let carbStore = carbStore {
            carbStore.getTotalRecentCarbValue { (value, error) -> Void in
                DispatchQueue.main.async {
                    if let value = value {
                        self.totalValueLabel.text = NumberFormatter.localizedString(from: NSNumber(value: value.quantity.doubleValue(for: carbStore.preferredUnit)), number: .none)
                        self.totalDateLabel.text = String(format: NSLocalizedString("com.loudnate.CarbKit.totalDateLabel", tableName: "CarbKit", value: "since %1$@", comment: "The format string describing the starting date of a total value. The first format argument is the localized date."), DateFormatter.localizedString(from: value.startDate as Date, dateStyle: .none, timeStyle: .short))
                    } else {
                        self.totalValueLabel.text = NumberFormatter.localizedString(from: 0, number: .none)
                        self.totalDateLabel.text = nil
                    }
                }
            }
        }
    }

    private var carbStoreObserver: Any? {
        willSet {
            if let observer = carbStoreObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    // MARK: - Table view data source

    public override func numberOfSections(in tableView: UITableView) -> Int {
        switch state {
        case .unknown, .unavailable, .authorizationRequired:
            return 0
        case .display:
            return 1
        }
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return carbEntries.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier, for: indexPath)

        if case .display = state, let carbStore = carbStore {
            let entry = carbEntries[indexPath.row]
            let value = NumberFormatter.localizedString(from: NSNumber(value: entry.quantity.doubleValue(for: carbStore.preferredUnit)), number: .none)

            var titleText = "\(value) \(carbStore.preferredUnit)"

            if let foodType = entry.foodType {
                titleText += ": \(foodType)"
            }

            cell.textLabel?.text = titleText

            var detailText = DateFormatter.localizedString(from: entry.startDate, dateStyle: .none, timeStyle: .short)

            if let absorptionTime = entry.absorptionTime {
                let minutes = NumberFormatter.localizedString(from: NSNumber(value: absorptionTime.minutes), number: .none)
                detailText += " + \(minutes) min"
            }

            cell.detailTextLabel?.text = detailText
        }
        return cell
    }

    public override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return carbEntries[indexPath.row].createdByCurrentApp
    }

    public override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete, case .display = state, let carbStore = carbStore {
            let entry = carbEntries.remove(at: indexPath.row)
            carbStore.deleteCarbEntry(entry, resultHandler: { (success, error) -> Void in
                DispatchQueue.main.async {
                    if success {
                        tableView.deleteRows(at: [indexPath], with: .automatic)
                        self.updateTimelyStats(nil)
                        self.updateTotal()

                        NotificationCenter.default.post(name: .CarbEntriesDidUpdate, object: self)
                    } else if let error = error {
                        self.presentAlertController(with: error)
                    }
                }
            })
        }
    }

    // MARK: - UITableViewDelegate

    public override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let entry = carbEntries[indexPath.row]

        if !entry.createdByCurrentApp {
            return nil
        }

        return indexPath
    }

    // MARK: - Navigation

    @IBAction func unwindFromEditing(_ segue: UIStoryboardSegue) {
        if let  editVC = segue.source as? CarbEntryEditViewController,
                let updatedEntry = editVC.updatedCarbEntry
        {
            if let originalEntry = editVC.originalCarbEntry {
                carbStore?.replaceCarbEntry(originalEntry, withEntry: updatedEntry) { (_, _, error) -> Void in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.presentAlertController(with: error)
                        } else {
                            self.reloadData()

                            NotificationCenter.default.post(name: .CarbEntriesDidUpdate, object: self)
                        }
                    }
                }
            } else {
                carbStore?.addCarbEntry(updatedEntry) { (_, _, error) -> Void in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.presentAlertController(with: error)
                        } else {
                            self.reloadData()

                            NotificationCenter.default.post(name: .CarbEntriesDidUpdate, object: self)
                        }
                    }
                }
            }
        }
    }

    public override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        var editVC = segue.destination as? CarbEntryEditViewController

        if editVC == nil, let navVC = segue.destination as? UINavigationController {
            editVC = navVC.viewControllers.first as? CarbEntryEditViewController
        }

        if let editVC = editVC {
            if let selectedCell = sender as? UITableViewCell, let indexPath = tableView.indexPath(for: selectedCell), indexPath.row < carbEntries.count {
                editVC.originalCarbEntry = carbEntries[indexPath.row]
            }

            editVC.defaultAbsorptionTimes = carbStore?.defaultAbsorptionTimes
        }
    }

    @IBAction func authorizeHealth(_ sender: Any) {
        if case .authorizationRequired = state, let carbStore = carbStore {
            carbStore.authorize { (success, error) in
                DispatchQueue.main.async {
                    if success {
                        self.state = .display
                    } else if let error = error {
                        self.presentAlertController(with: error)
                    }
                }
            }
        }
    }

}
