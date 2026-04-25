#include "backend.h"
#include <QJsonArray>

Backend::Backend(const QString &backendPath, QObject *parent)
    : QObject(parent)
{
    m_state["todos"]       = QVariantList();
    m_state["projects"]    = QVariantList();
    m_state["isAscending"] = true;
    m_state["filterText"]  = QString();

    m_process = new QProcess(this);
    m_process->setProgram(backendPath);

    connect(m_process, &QProcess::readyReadStandardOutput,
            this, &Backend::onReadyRead);
    connect(m_process, &QProcess::readyReadStandardError, this, [this]() {
        const QString msg = QString::fromUtf8(m_process->readAllStandardError()).trimmed();
        if (!msg.isEmpty())
            qDebug() << "[haskell]" << msg;
    });
    connect(m_process, &QProcess::started, this, [this]() {
        getAppState();
    });

    m_process->start();
}

Backend::~Backend()
{
    if (m_process->state() != QProcess::NotRunning) {
        m_process->closeWriteChannel();
        if (!m_process->waitForFinished(3000))
            m_process->kill();
    }
}

QVariantMap Backend::state() const { return m_state; }

void Backend::sendRequest(const QJsonObject &req)
{
    QByteArray data = QJsonDocument(req).toJson(QJsonDocument::Compact) + "\n";
    m_process->write(data);
}

void Backend::addTodo(const QString &title, int projectId)
{
    QJsonObject input;
    input["title"]     = title;
    input["projectId"] = projectId;

    QJsonObject req;
    req["action"] = "addTodo";
    req["input"]  = input;
    sendRequest(req);
}

void Backend::deleteTodo(int todoId)
{
    QJsonObject req;
    req["action"] = "deleteTodo";
    req["input"]  = QString::number(todoId);
    sendRequest(req);
}

void Backend::toggleTodo(int todoId)
{
    QJsonObject req;
    req["action"] = "toggleTodo";
    req["input"]  = QString::number(todoId);
    sendRequest(req);
}

void Backend::getAppState()
{
    QJsonObject req;
    req["action"] = "getAppState";
    sendRequest(req);
}

void Backend::sortAscending()
{
    QJsonObject req;
    req["action"] = "sortAscending";
    sendRequest(req);
}

void Backend::sortDescending()
{
    QJsonObject req;
    req["action"] = "sortDescending";
    sendRequest(req);
}

void Backend::setFilterText(const QString &text)
{
    QJsonObject req;
    req["action"] = "setTodoFilter";
    req["input"]  = text;
    sendRequest(req);
}

void Backend::addProject(const QString &name)
{
    QJsonObject req;
    req["action"] = "addProject";
    req["input"]  = name;
    sendRequest(req);
}

void Backend::deleteProject(int projectId)
{
    QJsonObject req;
    req["action"] = "deleteProject";
    req["input"]  = QString::number(projectId);
    sendRequest(req);
}

void Backend::renameProject(int projectId, const QString &newName)
{
    QJsonObject input;
    input["id"]   = projectId;
    input["name"] = newName;

    QJsonObject req;
    req["action"] = "renameProject";
    req["input"]  = input;
    sendRequest(req);
}

static QVariantList parseTodoList(const QJsonArray &arr)
{
    QVariantList list;
    for (const auto &item : arr) {
        QJsonObject todo = item.toObject();
        QVariantMap m;
        m["todoId"]        = todo["todoId"].toInt();
        m["title"]         = todo["todoTitle"].toString();
        m["done"]          = todo["todoDone"].toBool();
        m["todoProjectId"] = todo["todoProjectId"].toInt();
        list.append(m);
    }
    return list;
}

static QVariantList parseProjectList(const QJsonArray &arr)
{
    QVariantList list;
    for (const auto &item : arr) {
        QJsonObject proj = item.toObject();
        QVariantMap m;
        m["projectId"]   = proj["projectId"].toInt();
        m["projectName"] = proj["projectName"].toString();
        list.append(m);
    }
    return list;
}

void Backend::onReadyRead()
{
    while (m_process->canReadLine()) {
        QByteArray line = m_process->readLine().trimmed();
        if (line.isEmpty()) continue;

        QJsonDocument doc = QJsonDocument::fromJson(line);
        if (!doc.isObject()) continue;

        QJsonObject obj    = doc.object();
        QString     action = obj["action"].toString();
        int         ver    = obj["ver"].toInt();

        if (action == "getAppState") {
            QJsonObject result   = obj["result"].toObject();
            QJsonObject settings = result["settings"].toObject();
            m_state["todos"]       = parseTodoList(result["todos"].toArray());
            m_state["projects"]    = parseProjectList(result["projects"].toArray());
            m_state["isAscending"] = settings["sortOrder"].toString() == "Asc";
            m_state["filterText"]  = settings["todoFilterText"].toString();
            emit stateChanged();
        } else if (action == "getTodos") {
            m_state["todos"] = parseTodoList(obj["result"].toArray());
            emit stateChanged();
        } else if (action == "getProjects") {
            m_state["projects"] = parseProjectList(obj["result"].toArray());
            emit stateChanged();
        } else if (action == "addTodo"         || action == "deleteTodo"
                || action == "toggleTodo"      || action == "setTodoFilter"
                || action == "sortAscending"   || action == "sortDescending") {
            if (ver > m_versions.value("todos", 0)) {
                m_versions["todos"] = ver;
                if (action == "sortAscending")  m_state["isAscending"] = true;
                if (action == "sortDescending") m_state["isAscending"] = false;
                m_state["todos"] = parseTodoList(obj["result"].toArray());
                emit stateChanged();
            }
        } else if (action == "addProject"  || action == "deleteProject"
                || action == "renameProject") {
            if (ver > m_versions.value("projects", 0)) {
                m_versions["projects"] = ver;
                m_state["projects"] = parseProjectList(obj["result"].toArray());
                emit stateChanged();
            }
        }
    }
}

#include "moc_backend.cpp"
