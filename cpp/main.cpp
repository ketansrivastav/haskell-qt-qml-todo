#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#include <QDir>
#include <QDateTime>
#include <QTextStream>
#include <QStandardPaths>
#include "backend.h"

static QFile logFile;

static void messageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    QTextStream out(&logFile);
    QString level;
    switch (type) {
        case QtDebugMsg:    level = "DEBUG"; break;
        case QtWarningMsg:  level = "WARN";  break;
        case QtCriticalMsg: level = "ERROR"; break;
        case QtFatalMsg:    level = "FATAL"; break;
        default:            level = "INFO";  break;
    }
    QString source = ctx.file ? QString("[%1:%2]").arg(ctx.file).arg(ctx.line) : "";
    out << QDateTime::currentDateTime().toString("hh:mm:ss.zzz")
        << " [" << level << "] " << source << " " << msg << "\n";
    out.flush();
}

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("haskell-qt");

    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);
    logFile.setFileName(dataDir + "/app.log");
    logFile.open(QIODevice::Append | QIODevice::Text);
    qInstallMessageHandler(messageHandler);

    // Find the Haskell backend binary next to the Qt executable
    QString backendPath = QCoreApplication::applicationDirPath() + "/haskell-backend";
    if (!QFile::exists(backendPath)) {
        qCritical() << "Haskell backend not found at:" << backendPath;
        return 1;
    }

    Backend backend(backendPath);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);

    engine.load(QUrl::fromLocalFile(QStringLiteral(QML_DIR "/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
