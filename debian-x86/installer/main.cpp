#include <QApplication>
#include <QCheckBox>
#include <QCloseEvent>
#include <QFile>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QListWidget>
#include <QProcess>
#include <QProgressBar>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollBar>
#include <QScrollArea>
#include <QScroller>
#include <QStackedWidget>
#include <QTextEdit>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <functional>

// A small native wizard using the same Qt runtime as QOpenHD.
// All storage mutations remain in the independently guarded installation backend.
class Installer final : public QWidget {
    QStackedWidget *pages = new QStackedWidget;
    QListWidget *disks = new QListWidget;
    QLabel *diskStatus = new QLabel;
    QLabel *review = new QLabel;
    QLabel *stage = new QLabel;
    QLabel *failure = new QLabel;
    QCheckBox *erase = new QCheckBox("Erase every partition and all data on this disk");
    QCheckBox *backup = new QCheckBox("I have saved anything I need from this disk");
    QPushButton *next = nullptr;
    QPushButton *install = nullptr;
    QProgressBar *progress = new QProgressBar;
    QTextEdit *details = new QTextEdit;
    QProcess scanner, validator, writer;
    QJsonObject selected;
    QByteArray pending;
    bool busy = false;
    QString profile = "minimal";

    static QLabel *label(const QString &text, bool title = false) {
        auto *result = new QLabel(text);
        result->setWordWrap(true);
        if (title) result->setObjectName("title");
        return result;
    }
    QVBoxLayout *page(const QString &title, const QString &description) {
        auto *widget = new QWidget;
        auto *layout = new QVBoxLayout(widget);
        layout->setSpacing(12);
        layout->addWidget(label(title, true));
        layout->addWidget(label(description));
        pages->addWidget(widget);
        return layout;
    }
    static QPushButton *button(QVBoxLayout *layout, const QString &text,
                               const std::function<void()> &action, bool primary = false) {
        auto *result = new QPushButton(text);
        result->setMinimumHeight(52);
        if (primary) result->setObjectName("primary");
        layout->addWidget(result);
        QObject::connect(result, &QPushButton::clicked, result, action);
        return result;
    }
    static QString path(const QJsonObject &disk) { return disk["path"].toString(); }
    static QString identity(const QJsonObject &disk) {
        return path(disk) + "|" + disk["maj:min"].toString() + "|" +
               disk["serial"].toString() + "|" + disk["model"].toString() + "|" +
               QString::number(disk["size"].toDouble(), 'f', 0);
    }
    static bool occupied(const QJsonObject &disk) {
        const QString type = disk["type"].toString();
        if (type != "disk" && type != "part") return true;
        for (const auto &mount : disk["mountpoints"].toArray())
            if (!mount.toString().isEmpty()) return true;
        for (const auto &child : disk["children"].toArray())
            if (occupied(child.toObject())) return true;
        return false;
    }
    static QStringList scanArguments() {
        return {"--json", "--tree", "--bytes", "--output", "PATH,SIZE,MODEL,SERIAL,TRAN,TYPE,RO,MOUNTPOINTS,MAJ:MIN"};
    }
    void scan() {
        if (scanner.state() != QProcess::NotRunning) return;
        disks->clear();
        next->setEnabled(false);
        diskStatus->setText("Looking for installation disks…");
        scanner.start("lsblk", scanArguments());
    }
    void showFailure(const QString &message) {
        busy = false;
        failure->setText(message);
        pages->setCurrentIndex(5);
    }
    void startWrite() {
        if (!erase->isChecked() || !backup->isChecked() || busy) return;
        // Match the physical identity shown on the review screen, not merely /dev/sdX.
        QProcess check;
        check.start("lsblk", scanArguments());
        if (!check.waitForFinished(5000) || check.exitCode() != 0) {
            showFailure("The disk could not be checked. No installation was started.");
            return;
        }
        bool found = false;
        for (const auto &item : QJsonDocument::fromJson(check.readAllStandardOutput()).object()["blockdevices"].toArray()) {
            const auto disk = item.toObject();
            if (identity(disk) == identity(selected) && !occupied(disk) && !disk["ro"].toBool()) found = true;
        }
        if (!found) {
            showFailure("The selected disk changed or is now in use. Select the disk again. No installation was started.");
            return;
        }
        busy = true;
        progress->setValue(0);
        stage->setText("Preparing installation…");
        details->clear();
        pending.clear();
        pages->setCurrentIndex(3);
        writer.start("/usr/local/sbin/openhd-install", {"--target", path(selected), "--profile", profile});
    }
    void consume() {
        const QByteArray data = writer.readAllStandardOutput();
        details->moveCursor(QTextCursor::End);
        details->insertPlainText(QString::fromUtf8(data));
        details->verticalScrollBar()->setValue(details->verticalScrollBar()->maximum());
        pending += data;
        while (pending.contains('\n')) {
            const auto index = pending.indexOf('\n');
            const QString line = QString::fromUtf8(pending.left(index));
            pending.remove(0, index + 1);
            const auto match = QRegularExpression("^OPENHD_PROGRESS ([0-9]+) (.*)$").match(line);
            if (match.hasMatch()) {
                progress->setValue(match.captured(1).toInt());
                stage->setText(match.captured(2));
            }
        }
    }
protected:
    void closeEvent(QCloseEvent *event) override {
        if (busy) event->ignore(); else event->accept();
    }
public:
    Installer() {
        setWindowTitle("Install OpenHD OS");
        auto *outer = new QVBoxLayout(this);
        outer->setContentsMargins(24, 16, 24, 16);
        auto *brand = label("OPENHD  /  OS SETUP");
        brand->setObjectName("brand");
        outer->addWidget(brand);
        auto *scroll = new QScrollArea;
        scroll->setFrameShape(QFrame::NoFrame);
        scroll->setWidgetResizable(true);
        scroll->setWidget(pages);
        QScroller::grabGesture(scroll->viewport(), QScroller::TouchGesture);
        outer->addWidget(scroll, 1);

        auto *welcome = page("Welcome to OpenHD OS", "Run QOpenHD from this USB drive, or install OpenHD OS on this computer.");
        welcome->addStretch();
        button(welcome, "Start QOpenHD", [] { QApplication::quit(); });
        button(welcome, "Install OpenHD OS", [this] { pages->setCurrentIndex(1); scan(); }, true);
        welcome->addWidget(label("Installation works offline. Your OpenHD configuration will be copied to the installed system."));

        auto *choose = page("Choose where to install", "The running USB and disks already in use are unavailable. Select the disk that will hold OpenHD OS.");
        disks->setMinimumHeight(110);
        disks->setSpacing(8);
        choose->addWidget(disks, 1);
        diskStatus->setWordWrap(true);
        choose->addWidget(diskStatus);
        button(choose, "Refresh disks", [this] { scan(); });
        next = button(choose, "Continue", [this] {
            if (!disks->currentItem()) return;
            selected = disks->currentItem()->data(Qt::UserRole).toJsonObject();
            next->setEnabled(false);
            diskStatus->setText("Checking selected disk…");
            validator.start("/usr/local/sbin/openhd-install", {"--target", path(selected), "--dry-run"});
        }, true);
        next->setEnabled(false);
        button(choose, "Back", [this] { pages->setCurrentIndex(0); });
        connect(disks, &QListWidget::currentItemChanged, this, [this] { next->setEnabled(disks->currentItem() != nullptr); });
        connect(&scanner, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this](int code, QProcess::ExitStatus) {
            if (code != 0) { diskStatus->setText("Disks could not be read. Try refreshing."); return; }
            for (const auto &item : QJsonDocument::fromJson(scanner.readAllStandardOutput()).object()["blockdevices"].toArray()) {
                const auto disk = item.toObject();
                if (disk["type"].toString() != "disk") continue;
                const bool eligible = !disk["ro"].toBool() && !occupied(disk) && disk["size"].toDouble() >= 1073741824;
                const QString size = QString::number(disk["size"].toDouble() / 1073741824, 'f', 1) + " GiB";
                QString name = disk["model"].toString().trimmed();
                if (name.isEmpty()) name = "Storage disk";
                auto *row = new QListWidgetItem(name + "  ·  " + size + "  ·  " + path(disk) +
                    "\nSerial: " + (disk["serial"].toString().isEmpty() ? "unavailable" : disk["serial"].toString()) +
                    (eligible ? "" : "  — unavailable (in use, read-only or too small)"), disks);
                row->setSizeHint(QSize(0, 88));
                row->setData(Qt::UserRole, disk);
                if (!eligible) row->setFlags(Qt::NoItemFlags);
            }
            diskStatus->setText("Select a disk. All existing data on the selected disk will be erased.");
        });
        connect(&validator, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this](int code, QProcess::ExitStatus) {
            next->setEnabled(true);
            if (code != 0) { diskStatus->setText("This disk is unavailable. Refresh and choose another disk."); return; }
            review->setText("Install OpenHD OS on " + selected["model"].toString().trimmed() + "\n" +
                path(selected) + "  ·  " + QString::number(selected["size"].toDouble() / 1073741824, 'f', 1) + " GiB\nSerial: " +
                (selected["serial"].toString().isEmpty() ? "unavailable" : selected["serial"].toString()));
            erase->setChecked(false); backup->setChecked(false);
            pages->setCurrentIndex(2);
        });

        auto *confirm = page("Erase disk and install?", "This will permanently erase the selected disk, including other operating systems, files and recovery partitions.");
        review->setWordWrap(true);
        review->setObjectName("diskIdentity");
        confirm->addWidget(review);
        confirm->addStretch();
        erase->setMinimumHeight(44); backup->setMinimumHeight(44);
        confirm->addWidget(erase); confirm->addWidget(backup);
        install = button(confirm, "Erase disk and install OpenHD OS", [this] { startWrite(); }, true);
        install->setEnabled(false);
        auto consent = [this] { install->setEnabled(erase->isChecked() && backup->isChecked()); };
        connect(erase, &QCheckBox::toggled, this, consent);
        connect(backup, &QCheckBox::toggled, this, consent);
        button(confirm, "Back to disk selection", [this] { pages->setCurrentIndex(1); scan(); });

        auto *working = page("Installing OpenHD OS", "Keep this computer powered on and leave the USB drive connected until installation finishes.");
        stage->setWordWrap(true);
        working->addWidget(stage);
        progress->setMinimumHeight(28);
        working->addWidget(progress);
        details->setReadOnly(true);
        details->setVisible(false);
        working->addWidget(details, 1);
        working->addStretch();
        button(working, "Show / hide installation details", [this] { details->setVisible(!details->isVisible()); });

        auto *done = page("OpenHD OS is installed", "Your configuration has been copied. Restart this computer and remove the USB drive when the screen goes dark to start the installed system.");
        done->addStretch();
        button(done, "Restart computer", [this] { QProcess::startDetached("systemctl", {"reboot"}); }, true);
        button(done, "Shut down", [this] { QProcess::startDetached("systemctl", {"poweroff"}); });
        button(done, "Continue using USB", [] { QApplication::quit(); });

        auto *error = page("Installation could not finish", "The selected disk may contain an incomplete installation. Your running USB system is still available.");
        failure->setWordWrap(true);
        error->addWidget(failure);
        error->addStretch();
        button(error, "Choose a disk again", [this] { pages->setCurrentIndex(1); scan(); });
        button(error, "Start QOpenHD", [] { QApplication::quit(); });

        auto *unavailable = page("OpenHD-OS desktop is not included", "This compact image contains QOpenHD in minimal mode. Use the OpenHD-OS desktop image for the full desktop. No disk has been changed.");
        unavailable->addStretch();
        button(unavailable, "Start QOpenHD in minimal mode", [] { QApplication::quit(); }, true);

        writer.setProcessChannelMode(QProcess::MergedChannels);
        connect(&writer, &QProcess::started, this, [this] {
            writer.write(("ERASE " + path(selected) + "\n").toUtf8());
            writer.closeWriteChannel();
        });
        connect(&writer, &QProcess::readyReadStandardOutput, this, [this] { consume(); });
        connect(&writer, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this](int code, QProcess::ExitStatus status) {
            consume(); busy = false;
            if (code == 0 && status == QProcess::NormalExit) pages->setCurrentIndex(4);
            else showFailure("The installer stopped.\n" + details->toPlainText().right(1800));
        });
        connect(&writer, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) showFailure("The installation backend could not start. No installation was started.");
        });
        connect(&scanner, &QProcess::errorOccurred, this, [this] { diskStatus->setText("Disk detection could not start. Try refreshing."); });
        connect(&validator, &QProcess::errorOccurred, this, [this] { next->setEnabled(true); diskStatus->setText("The disk check could not start."); });
        setStyleSheet(R"(
            QWidget { background:#101820; color:#edf4fa; font-family:'DejaVu Sans'; font-size:16px; }
            QLabel#brand { color:#36c7f4; font-size:18px; font-weight:bold; padding:4px 0 12px; }
            QLabel#title { font-size:28px; font-weight:bold; padding:8px 0; }
            QLabel#diskIdentity { background:#1b2b38; border-radius:12px; padding:18px; }
            QPushButton { background:#233645; border:1px solid #405a6c; border-radius:10px; padding:10px; }
            QPushButton:hover, QPushButton:focus { border:2px solid #36c7f4; }
            QPushButton#primary { background:#30c5ef; color:#081720; font-weight:bold; }
            QPushButton:disabled { background:#1c2730; color:#697d8b; border-color:#293b48; }
            QPushButton#primary:disabled { background:#1c2730; color:#697d8b; border-color:#293b48; }
            QListWidget { background:#162430; border:1px solid #405a6c; border-radius:10px; }
            QListWidget::item { padding:8px; border-radius:6px; }
            QListWidget::item:selected { background:#24536d; }
            QListWidget::item:disabled { color:#728390; }
            QCheckBox::indicator { width:30px; height:30px; }
            QProgressBar { border:1px solid #405a6c; border-radius:8px; text-align:center; }
            QProgressBar::chunk { background:#2385a3; border-radius:7px; }
            QTextEdit { font-size:13px; background:#0a1117; border:1px solid #405a6c; }
        )");
        if (QFile::exists("/proc/cmdline")) {
            QFile commandLine("/proc/cmdline");
            if (commandLine.open(QIODevice::ReadOnly)) {
                const auto arguments = commandLine.readAll().trimmed().split(' ');
                const bool desktopStart = arguments.contains("openhd.mode=desktop");
                if (arguments.contains("openhd.profile=desktop")) profile = "desktop";
                if ((desktopStart || profile == "desktop") && !QFile::exists("/usr/bin/Hyprland")) {
                    pages->setCurrentIndex(6);
                } else if (desktopStart) {
                    QTimer::singleShot(0, [] { QApplication::quit(); });
                } else if (arguments.contains("openhd.install")) {
                    pages->setCurrentIndex(1);
                    QTimer::singleShot(0, this, [this] { scan(); });
                }
            }
        }
        connect(pages, &QStackedWidget::currentChanged, this, [](int index) {
            qInfo() << "OpenHD installer page:" << index;
        });
        qInfo() << "OpenHD installer page:" << pages->currentIndex();
    }
};

int main(int argc, char **argv) {
    // Firmware/simpledrm may enumerate before the actual Intel/AMD GPU. Prefer
    // a card with a connected output and let EGLFS configure that GPU directly.
    if (qEnvironmentVariableIsEmpty("QT_QPA_EGLFS_KMS_CONFIG")) {
        const QDir drm("/sys/class/drm");
        for (const auto &card : drm.entryList({"card*"}, QDir::Dirs, QDir::Name)) {
            if (!QRegularExpression("^card[0-9]+$").match(card).hasMatch()) continue;
            const QString driver = QFileInfo(drm.filePath(card + "/device/driver")).canonicalFilePath();
            if (driver.endsWith("/simpledrm")) continue;
            bool connected = false;
            for (const auto &output : drm.entryList({card + "-*"}, QDir::Dirs)) {
                QFile status(drm.filePath(output + "/status"));
                if (status.open(QIODevice::ReadOnly) && status.readAll().trimmed() == "connected") connected = true;
            }
            if (!connected) continue;
            QFile config("/run/openhd-installer-kms.json");
            if (config.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                config.write(QJsonDocument(QJsonObject{{"device", "/dev/dri/" + card}, {"hwcursor", false}}).toJson());
                config.close();
                qputenv("QT_QPA_EGLFS_KMS_CONFIG", config.fileName().toUtf8());
            }
            break;
        }
    }
    QApplication app(argc, argv);
    QApplication::setApplicationName("OpenHD OS Installer");
    Installer installer;
    installer.showFullScreen();
    return app.exec();
}
